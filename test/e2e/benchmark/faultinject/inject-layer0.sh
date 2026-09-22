#!/usr/bin/env bash
# inject-layer0.sh — Layer 0 触发注入器：Node 归属漂移
#
# 场景：将当前分配给某个 Scheduler 实例的节点子集（默认 10%）的
#       eno.io/scheduler-name 注解改写为另一个 Scheduler 实例，模拟
#       Dispatcher node-shuffler 触发的强制重分区。原持有者随后的 Bind
#       尝试会被 Layer 0 拦截，走 Layer 3 全局回退。
#
# ENO 三实例部署中每个 Scheduler 实例都有唯一的 --eno-scheduler-name
# (eno-scheduler-0/-1/-2)；Node 的 eno.io/scheduler-name 注解也存储实
# 例级名称。本脚本在这些实例之间做归属漂移。
#
# 用法：
#   inject-layer0.sh <out_dir> [--fraction 0.1] [--from <sched>] [--to <sched>]
#
# out_dir     实验结果目录
# --fraction  从 FROM Scheduler 名下节点中随机抽取的比例 (默认 0.1)
# --from      源 Scheduler 实例名 (默认 eno-scheduler-0)
# --to        目标 Scheduler 实例名 (默认 eno-scheduler-1)
#
# 输出：
#   ${out_dir}/inject-manifest.json  被 patch 的节点清单 + 起止时间
#   ${out_dir}/inject-events.log     单行事件日志

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${BENCHMARK_DIR}/config.sh"
source "${BENCHMARK_DIR}/lib/utils.sh"

OUT_DIR="${1:?用法: inject-layer0.sh <out_dir> [--fraction N] [--from X] [--to Y]}"
shift
FRACTION="0.1"
FROM_SCHED="eno-scheduler-0"
TO_SCHED="eno-scheduler-1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fraction) FRACTION="$2"; shift 2 ;;
    --from)     FROM_SCHED="$2"; shift 2 ;;
    --to)       TO_SCHED="$2"; shift 2 ;;
    *)          log_error "未知参数: $1"; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"
MANIFEST="${OUT_DIR}/inject-manifest.json"
EVENTS="${OUT_DIR}/inject-events.log"
NODES_FILE="$(mktemp)"
trap 'rm -f "$NODES_FILE"' EXIT

log_info "Layer0 注入: from=${FROM_SCHED} → to=${TO_SCHED}, fraction=${FRACTION}"

# ── 收集当前归属 = FROM_SCHED 的节点，写入 NODES_FILE ──
kubectl get nodes -l fake.byted.org/node -o json \
  | python3 - "$FROM_SCHED" "$FRACTION" > "$NODES_FILE" <<'PY'
import json, os, random, sys
from_sched, frac = sys.argv[1], float(sys.argv[2])
data = json.load(sys.stdin)
owned, unowned = [], []
for item in data.get("items", []):
    ann = (item.get("metadata", {}).get("annotations") or {})
    owner = ann.get("eno.io/scheduler-name", "")
    name = item["metadata"]["name"]
    if owner == from_sched: owned.append(name)
    elif owner == "":       unowned.append(name)

# stderr 里附带全池 owners 统计，便于事后审阅
owners = {}
for item in data.get("items", []):
    ann = (item.get("metadata", {}).get("annotations") or {})
    owner = ann.get("eno.io/scheduler-name", "<none>")
    owners[owner] = owners.get(owner, 0) + 1
sys.stderr.write(f"[layer0] owner-distribution: {owners}\n")

pool = owned if owned else unowned
if not pool:
    sys.stderr.write(f"[layer0] no nodes owned by {from_sched!r} (and no unowned fallback); nothing to patch\n")
    print(f"POOL_SIZE=0")
    print(f"PICKED=0")
    sys.exit(0)

random.seed(42)
k = max(1, int(len(pool) * frac))
picked = random.sample(pool, k)
print(f"POOL_SIZE={len(pool)}")
print(f"PICKED={k}")
for n in picked: print(n)
PY

POOL_SIZE=$(grep '^POOL_SIZE=' "$NODES_FILE" | head -n1 | cut -d= -f2)
PICKED_CNT=$(grep '^PICKED=' "$NODES_FILE" | head -n1 | cut -d= -f2)
if [[ "${POOL_SIZE:-0}" == "0" || "${PICKED_CNT:-0}" == "0" ]]; then
  log_error "无节点可 patch (from=${FROM_SCHED}); 请确认 Dispatcher 已完成分区，且 --from 名称与实际实例名匹配"
  exit 1
fi
log_info "  匹配节点池 ${POOL_SIZE} 个，抽取 ${PICKED_CNT} 个进行注解漂移"

START_TS=$(date +%s)
START_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$START_ISO] inject.begin from=${FROM_SCHED} to=${TO_SCHED} target=${PICKED_CNT}" >> "$EVENTS"

# ── 执行 patch ──
PATCHED=0
FAILED=0
PATCH_JSON="{\"metadata\":{\"annotations\":{\"eno.io/scheduler-name\":\"${TO_SCHED}\"}}}"
while IFS= read -r node; do
  case "$node" in POOL_SIZE=*|PICKED=*|"") continue ;; esac
  if kubectl patch node "$node" --type=merge -p "$PATCH_JSON" >/dev/null 2>&1; then
    PATCHED=$((PATCHED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "[$(date -u +%FT%TZ)] inject.patch_failed node=${node}" >> "$EVENTS"
  fi
done < "$NODES_FILE"

END_TS=$(date +%s)
END_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DURATION=$((END_TS - START_TS))
echo "[$END_ISO] inject.end patched=${PATCHED} failed=${FAILED} duration=${DURATION}s" >> "$EVENTS"
log_info "  ✓ patch 完成: ${PATCHED} 成功 / ${FAILED} 失败 / 用时 ${DURATION}s"

# ── 写 manifest ──
python3 - "$MANIFEST" "$FROM_SCHED" "$TO_SCHED" "$FRACTION" \
  "$POOL_SIZE" "$PICKED_CNT" "$PATCHED" "$FAILED" "$START_TS" "$END_TS" "$NODES_FILE" <<'PY'
import json, sys
(_, path, frm, to, frac, pool, picked, patched, failed, s, e, nodes_file) = sys.argv
nodes = []
with open(nodes_file) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        if line.startswith("POOL_SIZE=") or line.startswith("PICKED="): continue
        nodes.append(line)
manifest = {
    "layer": "layer0",
    "from_scheduler": frm,
    "to_scheduler":   to,
    "fraction":       float(frac),
    "pool_size":      int(pool),
    "target_count":   int(picked),
    "patched_count":  int(patched),
    "failed_count":   int(failed),
    "inject_start_ts": int(s),
    "inject_end_ts":   int(e),
    "nodes": nodes,
}
with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
print(path)
PY
log_info "  ✓ manifest: ${MANIFEST}"
