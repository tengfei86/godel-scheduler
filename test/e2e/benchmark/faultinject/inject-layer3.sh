#!/usr/bin/env bash
# inject-layer3.sh — Layer 3 触发注入器：Scheduler 实例失活
#
# 场景：force-delete 一个 Scheduler Pod 使其在 Dispatcher 视角上等价于
#       "进程崩溃"。Scheduler Maintainer 通过心跳/Lease 感知失活，
#       PodStateReconciler 扫描其名下 Dispatched-但-未 Bind 的 Pod，
#       重置为 Pending 并交由存活实例接管。Deployment 会在数秒内重建
#       被杀 Pod，供观测恢复期。
#
# 用法：
#   inject-layer3.sh <out_dir> [--target <pod|deployment>] [--namespace <ns>]
#
# out_dir      实验结果目录
# --target     被删除对象的 label 或 Deployment/Pod 名（默认: 挑选一个 running scheduler pod）
# --namespace  ENO Scheduler 所在命名空间（默认: config.sh 中的 ENO_NAMESPACE）
#
# 输出：
#   ${out_dir}/inject-manifest.json  被删除对象 + 起止时间 + 重建时间戳
#   ${out_dir}/inject-events.log     单行事件日志

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${BENCHMARK_DIR}/config.sh"
source "${BENCHMARK_DIR}/lib/utils.sh"

OUT_DIR="${1:?用法: inject-layer3.sh <out_dir> [--target <name>] [--namespace <ns>]}"
shift
TARGET=""
NS="${ENO_NAMESPACE}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)    TARGET="$2"; shift 2 ;;
    --namespace) NS="$2"; shift 2 ;;
    *)           log_error "未知参数: $1"; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"
MANIFEST="${OUT_DIR}/inject-manifest.json"
EVENTS="${OUT_DIR}/inject-events.log"

# ── 挑选一个 Running 的 Scheduler Pod ──
if [[ -z "$TARGET" ]]; then
  TARGET=$(kubectl get pods -n "$NS" -l app=eno-scheduler \
              --field-selector=status.phase=Running \
              -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$TARGET" ]]; then
  log_error "未找到 Running 的 eno-scheduler Pod (ns=${NS})"
  exit 1
fi

# 记录被杀 Pod 所属 Deployment（用于观察重建），以及它的 eno-scheduler-name label
DEPLOY=$(kubectl get pod "$TARGET" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
SCHED_LABEL=$(kubectl get pod "$TARGET" -n "$NS" -o jsonpath='{.metadata.labels.eno-scheduler-name}' 2>/dev/null || true)
if [[ -n "$DEPLOY" ]]; then
  # ownerRef 通常是 ReplicaSet；再往上一层拿 Deployment
  RS_OWNER=$(kubectl get rs "$DEPLOY" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
  [[ -n "$RS_OWNER" ]] && DEPLOY="$RS_OWNER"
fi

log_info "Layer3 注入: 目标 Pod=${TARGET} (deploy=${DEPLOY:-?}, sched=${SCHED_LABEL:-?})"

# ── 记录注入前的兄弟 Pod 名单，用于事后核对"存活实例" ──
SIBLINGS=$(kubectl get pods -n "$NS" -l app=eno-scheduler \
             --field-selector=status.phase=Running \
             -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v "^${TARGET}$" || true)

START_TS=$(date +%s)
START_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$START_ISO] inject.begin pod=${TARGET} deploy=${DEPLOY:-?} sched=${SCHED_LABEL:-?}" >> "$EVENTS"

# ── force-delete ──
if ! kubectl delete pod "$TARGET" -n "$NS" --grace-period=0 --force >/dev/null 2>&1; then
  log_error "删除 Pod 失败: ${TARGET}"
  echo "[$(date -u +%FT%TZ)] inject.delete_failed pod=${TARGET}" >> "$EVENTS"
  exit 1
fi
KILLED_TS=$(date +%s)
KILLED_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$KILLED_ISO] inject.killed pod=${TARGET}" >> "$EVENTS"
log_info "  ✓ Pod 已删除: ${TARGET}"

# ── 等待 Deployment 重建（最多 90 秒）──
RESTORED_TS=""
RESTORED_POD=""
if [[ -n "$DEPLOY" ]]; then
  # 兼容 Deployment 与 StatefulSet；此处走通用 label 匹配路径
  for i in $(seq 1 90); do
    NEW=$(kubectl get pods -n "$NS" -l "eno-scheduler-name=${SCHED_LABEL}" \
             --field-selector=status.phase=Running \
             -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$NEW" && "$NEW" != "$TARGET" ]]; then
      RESTORED_POD="$NEW"
      RESTORED_TS=$(date +%s)
      break
    fi
    sleep 1
  done
fi

END_TS=$(date +%s)
END_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ -n "$RESTORED_TS" ]]; then
  RECOVER=$((RESTORED_TS - KILLED_TS))
  echo "[$(date -u -r "$RESTORED_TS" +%FT%TZ 2>/dev/null || date -u -d @"$RESTORED_TS" +%FT%TZ)] inject.restored pod=${RESTORED_POD} recover=${RECOVER}s" >> "$EVENTS"
  log_info "  ✓ 实例重建: ${RESTORED_POD} (耗时 ${RECOVER}s)"
else
  echo "[$END_ISO] inject.not_restored (>90s)" >> "$EVENTS"
  log_warn "  实例在 90s 内未被重建"
fi

# ── 写 manifest ──
python3 - "$MANIFEST" "$TARGET" "$DEPLOY" "$SCHED_LABEL" "$START_TS" "$KILLED_TS" \
  "${RESTORED_TS:-0}" "${RESTORED_POD:-}" "$END_TS" "$SIBLINGS" <<'PY'
import json, sys
(_, path, target, deploy, sched, s, k, r, rp, e, siblings_str) = sys.argv
siblings = [x for x in siblings_str.split() if x]
manifest = {
    "layer": "layer3",
    "target_pod":       target,
    "target_deployment": deploy,
    "target_scheduler": sched,
    "inject_start_ts":  int(s),
    "killed_ts":        int(k),
    "restored_ts":      int(r) if int(r) else None,
    "restored_pod":     rp or None,
    "inject_end_ts":    int(e),
    "siblings":         siblings,
}
with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
print(path)
PY
log_info "  ✓ manifest: ${MANIFEST}"
