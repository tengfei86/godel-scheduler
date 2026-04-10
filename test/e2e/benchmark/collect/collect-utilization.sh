#!/usr/bin/env bash
# collect/collect-utilization.sh — 采集节点资源分布快照
#
# 输出 CSV 格式到 stdout:
#   node,cpu_requested,cpu_allocatable,mem_requested,mem_allocatable,pod_count
#
# 用法:
#   ./collect-utilization.sh > utilization.csv
#
# 性能: 使用 jsonpath + awk 流式聚合，支持 30000+ 节点 / 800K+ Pod

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_stderr() { echo "[collect-utilization] $*" >&2; }

log_stderr "采集节点资源分布..."

# CSV header
echo "node,cpu_requested,cpu_allocatable,mem_requested,mem_allocatable,pod_count"

# ── Step 1: 流式提取 Pod 资源请求，按节点聚合 ──
# 只取 nodeName + 每个容器的 cpu/mem requests，不加载完整 JSON
POD_AGG_FILE=$(mktemp)
trap 'rm -f "$POD_AGG_FILE"' EXIT

kubectl get pods -n bench \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\t"}{range .spec.containers[*]}{.resources.requests.cpu}{"\t"}{.resources.requests.memory}{"\t"}{end}{"\n"}{end}' \
  2>/dev/null | awk -F'\t' '
  function parse_cpu(s) {
    if (s == "" || s == "0") return 0
    if (s ~ /m$/) { gsub(/m$/, "", s); return s + 0 }
    return (s + 0) * 1000
  }
  function parse_mem(s) {
    if (s == "" || s == "0") return 0
    if (s ~ /Ki$/) { gsub(/Ki$/, "", s); return (s + 0) * 1024 }
    if (s ~ /Mi$/) { gsub(/Mi$/, "", s); return (s + 0) * 1048576 }
    if (s ~ /Gi$/) { gsub(/Gi$/, "", s); return (s + 0) * 1073741824 }
    return s + 0
  }
  NF >= 1 && $1 != "" {
    node = $1
    cpu = 0; mem = 0
    for (i = 2; i <= NF; i += 2) {
      cpu += parse_cpu($i)
      if (i+1 <= NF) mem += parse_mem($(i+1))
    }
    node_cpu[node] += cpu
    node_mem[node] += mem
    node_cnt[node] += 1
  }
  END {
    for (n in node_cpu) {
      printf "%s\t%d\t%d\t%d\n", n, node_cpu[n], node_mem[n], node_cnt[n]
    }
  }
' > "$POD_AGG_FILE"

log_stderr "  Pod 聚合完成: $(wc -l < "$POD_AGG_FILE") 个节点有 Pod"

# ── Step 2: 流式提取节点 allocatable，与 Pod 聚合结果合并 ──
kubectl get nodes -l fake.byted.org/node \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.cpu}{"\t"}{.status.allocatable.memory}{"\n"}{end}' \
  2>/dev/null | awk -F'\t' -v pod_file="$POD_AGG_FILE" '
  function parse_cpu(s) {
    if (s == "" || s == "0") return 0
    if (s ~ /m$/) { gsub(/m$/, "", s); return s + 0 }
    return (s + 0) * 1000
  }
  function parse_mem(s) {
    if (s == "" || s == "0") return 0
    if (s ~ /Ki$/) { gsub(/Ki$/, "", s); return (s + 0) * 1024 }
    if (s ~ /Mi$/) { gsub(/Mi$/, "", s); return (s + 0) * 1048576 }
    if (s ~ /Gi$/) { gsub(/Gi$/, "", s); return (s + 0) * 1073741824 }
    return s + 0
  }
  BEGIN {
    while ((getline line < pod_file) > 0) {
      split(line, f, "\t")
      pcpu[f[1]] = f[2]
      pmem[f[1]] = f[3]
      pcnt[f[1]] = f[4]
    }
    close(pod_file)
  }
  NF >= 3 {
    name = $1
    cpu_alloc = parse_cpu($2)
    mem_alloc = parse_mem($3)
    cpu_req = (name in pcpu) ? pcpu[name] : 0
    mem_req = (name in pmem) ? pmem[name] : 0
    cnt     = (name in pcnt) ? pcnt[name] : 0
    printf "%s,%d,%d,%d,%d,%d\n", name, cpu_req, cpu_alloc, mem_req, mem_alloc, cnt
    node_count++
  }
  END {
    printf "[collect-utilization] ✓ 采集完成: %d 个节点\n", node_count > "/dev/stderr"
  }
'
