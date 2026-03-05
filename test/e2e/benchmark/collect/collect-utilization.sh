#!/bin/bash
# collect/collect-utilization.sh — 采集节点资源分布快照
#
# 输出 CSV 格式到 stdout:
#   node,cpu_requested,cpu_allocatable,mem_requested,mem_allocatable,pod_count
#
# 用法:
#   ./collect-utilization.sh > utilization.csv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 不加载 utils.sh 避免 log 输出干扰 CSV;  仅在 stderr 打日志
log_stderr() { echo "[collect-utilization] $*" >&2; }

log_stderr "采集节点资源分布..."

# CSV header
echo "node,cpu_requested,cpu_allocatable,mem_requested,mem_allocatable,pod_count"

# 获取所有 KWOK 节点的 allocatable 资源
NODES_JSON=$(kubectl get nodes -l fake.byted.org/node -o json 2>/dev/null)
if [[ -z "$NODES_JSON" ]] || [[ "$NODES_JSON" == "null" ]]; then
  log_stderr "无 KWOK 节点"
  exit 0
fi

# 获取所有 bench namespace 中 Pod 的资源请求
PODS_JSON=$(kubectl get pods -n bench -o json 2>/dev/null)

# 使用 jq 一次性计算每节点的资源利用率
echo "$NODES_JSON" | jq -r --argjson pods "$PODS_JSON" '
  # 构建节点到 Pod 资源请求的映射
  ($pods.items // [] | group_by(.spec.nodeName) |
    map({
      key: (.[0].spec.nodeName // "unscheduled"),
      value: {
        cpu_requested: ([.[].spec.containers[].resources.requests.cpu // "0" |
          if endswith("m") then (rtrimstr("m") | tonumber)
          else (tonumber * 1000)
          end] | add),
        mem_requested: ([.[].spec.containers[].resources.requests.memory // "0" |
          if endswith("Mi") then (rtrimstr("Mi") | tonumber * 1048576)
          elif endswith("Gi") then (rtrimstr("Gi") | tonumber * 1073741824)
          elif endswith("Ki") then (rtrimstr("Ki") | tonumber * 1024)
          else tonumber
          end] | add),
        pod_count: length
      }
    }) | from_entries
  ) as $pod_map |
  .items[] |
  .metadata.name as $name |
  (.status.allocatable.cpu // "0" |
    if endswith("m") then (rtrimstr("m") | tonumber)
    else (tonumber * 1000)
    end
  ) as $cpu_alloc |
  (.status.allocatable.memory // "0" |
    if endswith("Mi") then (rtrimstr("Mi") | tonumber * 1048576)
    elif endswith("Gi") then (rtrimstr("Gi") | tonumber * 1073741824)
    elif endswith("Ki") then (rtrimstr("Ki") | tonumber * 1024)
    else tonumber
    end
  ) as $mem_alloc |
  ($pod_map[$name].cpu_requested // 0) as $cpu_req |
  ($pod_map[$name].mem_requested // 0) as $mem_req |
  ($pod_map[$name].pod_count // 0) as $pc |
  "\($name),\($cpu_req),\($cpu_alloc),\($mem_req),\($mem_alloc),\($pc)"
' 2>/dev/null || {
  # 如果复杂 jq 失败，使用简化版本
  log_stderr "jq 复杂查询失败，使用简化版"

  # 简化版: 逐节点查询
  echo "$NODES_JSON" | jq -r '.items[].metadata.name' | while read -r node_name; do
    cpu_alloc=$(echo "$NODES_JSON" | jq -r ".items[] | select(.metadata.name==\"${node_name}\") | .status.allocatable.cpu // \"0\"")
    mem_alloc=$(echo "$NODES_JSON" | jq -r ".items[] | select(.metadata.name==\"${node_name}\") | .status.allocatable.memory // \"0\"")

    # 统计该节点上的 Pod 数量
    pod_count=$(echo "$PODS_JSON" | jq "[.items[] | select(.spec.nodeName==\"${node_name}\")] | length" 2>/dev/null || echo "0")

    echo "${node_name},0,${cpu_alloc},0,${mem_alloc},${pod_count}"
  done
}

NODE_COUNT=$(echo "$NODES_JSON" | jq '.items | length')
log_stderr "✓ 采集完成: ${NODE_COUNT} 个节点"
