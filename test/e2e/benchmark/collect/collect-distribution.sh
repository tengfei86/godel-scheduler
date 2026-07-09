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
#   annotation_domain: godel.bytedance.com | eno.io (默认 eno.io)

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_stderr() { echo "[collect-distribution] $*" >&2; }

# 注解域：支持原始 godel 和修改后的 eno
ANNO_DOMAIN="${1:-eno.io}"
SELECTED_SCHEDULER_KEY="${ANNO_DOMAIN}/selected-scheduler"

log_stderr "采集 Pod 分布 (annotation domain: ${ANNO_DOMAIN:-<none, 使用 spec.schedulerName>})..."

# CSV header
echo "node,pod_count,scheduler"

# 获取所有 bench namespace Pod 数据
PODS_JSON=$(kubectl get pods -n bench -o json 2>/dev/null)

if [[ -z "$PODS_JSON" ]] || [[ "$(echo "$PODS_JSON" | jq '.items | length')" == "0" ]]; then
  log_stderr "bench namespace 中无 Pod"
  exit 0
fi

# 每节点 Pod 数 + 所属 Scheduler
# kube-scheduler/volcano/koordinator 不写自定义 annotation，回退到 spec.schedulerName
echo "$PODS_JSON" | jq -r '
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
' | jq -rs '
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
  # 简化版本
  log_stderr "jq 复杂查询失败，使用简化版"
  kubectl get pods -n bench -o json | \
    jq -r '.items[] | select(.spec.nodeName != null) | "\(.spec.nodeName),\(.spec.schedulerName // "unknown")"' | \
    sort | uniq -c | sort -rn | \
    awk '{split($2,a,","); print a[1]","$1","a[2]}'
}

# 输出汇总到 stderr
TOTAL_PODS=$(echo "$PODS_JSON" | jq '.items | length')
SCHEDULED=$(echo "$PODS_JSON" | jq '[.items[] | select(.spec.nodeName != null)] | length')
UNIQUE_NODES=$(echo "$PODS_JSON" | jq '[.items[] | select(.spec.nodeName != null) | .spec.nodeName] | unique | length')

log_stderr "✓ 采集完成: ${SCHEDULED}/${TOTAL_PODS} Pod 已调度到 ${UNIQUE_NODES} 个节点"

# 输出每 Scheduler 分区的汇总（stderr）
log_stderr "Scheduler 分区分布:"
echo "$PODS_JSON" | jq -r '
  [.items[] | (
    if .metadata.annotations["'"${SELECTED_SCHEDULER_KEY}"'"] then
      .metadata.annotations["'"${SELECTED_SCHEDULER_KEY}"'"]
    else
      (.spec.schedulerName // "unknown")
    end
  )] |
  group_by(.) | map({scheduler: .[0], count: length}) | sort_by(-.count) |
  .[] | "  \(.scheduler): \(.count) pods"
' 2>/dev/null >&2 || true
