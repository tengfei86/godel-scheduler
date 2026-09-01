#!/usr/bin/env bash
# collect/collect-distribution.sh — 采集 Pod 分布快照
#
# 输出 CSV 格式到 stdout:
#   node,pod_count,scheduler
#
# 同时采集每 Scheduler 分区的 Pod 数和每节点 Pod 数。
#
# 用法:
#   ./collect-distribution.sh [annotation_domain]
#   annotation_domain: godel.bytedance.com | eno.io | "" (kube-scheduler/volcano/koordinator 留空，回退 spec.schedulerName)

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_stderr() { echo "[collect-distribution] $*" >&2; }

# 注解域：godel.bytedance.com | eno.io | 空字符串（kube-scheduler/volcano/koordinator）
ANNO_DOMAIN="${1:-}"
SELECTED_SCHEDULER_KEY="${ANNO_DOMAIN}/selected-scheduler"

log_stderr "采集 Pod 分布 (annotation domain: ${ANNO_DOMAIN:-<none, 使用 spec.schedulerName>})..."

# CSV header
echo "node,pod_count,scheduler"

# 获取所有 bench namespace Pod 数据
# 注意: 大规模场景 (s4/s5, 数十万 Pod, JSON 数 GB) 下不能用 $(...) 把 kubectl 输出
# 塞进 bash 变量 —— command substitution 的 buffer 增长会 size_t 溢出，
# 触发 "xrealloc: cannot allocate 18446744...bytes"。这里落盘到临时文件，
# 后续 jq 直接读文件，全程绕开 bash buffer。
PODS_FILE="$(mktemp -t pods-distribution.XXXXXX.json)"
trap 'rm -f "$PODS_FILE"' EXIT
kubectl get pods -n bench -o json > "$PODS_FILE" 2>/dev/null || true

if [[ ! -s "$PODS_FILE" ]] || [[ "$(jq '.items | length' "$PODS_FILE")" == "0" ]]; then
  log_stderr "bench namespace 中无 Pod"
  exit 0
fi

# 每节点 Pod 数 + 所属 Scheduler
# kube-scheduler/volcano/koordinator 不写自定义 annotation，回退到 spec.schedulerName
jq -r '
  .items[] |
  select(.spec.nodeName != null) |
  {
    node: .spec.nodeName,
    scheduler: (
      if .metadata.annotations["'"${SELECTED_SCHEDULER_KEY}"'"] then
        .metadata.annotations["'"${SELECTED_SCHEDULER_KEY}"'"]
      else
        (.spec.schedulerName // "unknown")
      end
    )
  }
' "$PODS_FILE" | jq -rs '
  group_by(.node) |
  map({
    node: .[0].node,
    pod_count: length,
    scheduler: (map(.scheduler) | group_by(.) | sort_by(-length) | .[0][0])
  }) |
  sort_by(-.pod_count) |
  .[] |
  "\(.node),\(.pod_count),\(.scheduler)"
' 2>/dev/null || {
  # 简化版本 —— 复用已落盘的 PODS_FILE，避免再打一次 kubectl
  log_stderr "jq 复杂查询失败，使用简化版"
  jq -r '.items[] | select(.spec.nodeName != null) | "\(.spec.nodeName),\(.spec.schedulerName // "unknown")"' "$PODS_FILE" | \
    sort | uniq -c | sort -rn | \
    awk '{split($2,a,","); print a[1]","$1","a[2]}'
}

# 输出汇总到 stderr
TOTAL_PODS=$(jq '.items | length' "$PODS_FILE")
SCHEDULED=$(jq '[.items[] | select(.spec.nodeName != null)] | length' "$PODS_FILE")
UNIQUE_NODES=$(jq '[.items[] | select(.spec.nodeName != null) | .spec.nodeName] | unique | length' "$PODS_FILE")

log_stderr "✓ 采集完成: ${SCHEDULED}/${TOTAL_PODS} Pod 已调度到 ${UNIQUE_NODES} 个节点"

# 输出每 Scheduler 分区的汇总（stderr）
log_stderr "Scheduler 分区分布:"
jq -r '
  [.items[] | (
    if .metadata.annotations["'"${SELECTED_SCHEDULER_KEY}"'"] then
      .metadata.annotations["'"${SELECTED_SCHEDULER_KEY}"'"]
    else
      (.spec.schedulerName // "unknown")
    end
  )] |
  group_by(.) | map({scheduler: .[0], count: length}) | sort_by(-.count) |
  .[] | "  \(.scheduler): \(.count) pods"
' "$PODS_FILE" 2>/dev/null >&2 || true
