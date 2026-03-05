#!/bin/bash
# workloads/workload-matrix.sh — W1~W8 负载场景参数定义
#
# 被 create-pods.sh 和 run-experiment.sh 调用。
# 定义每个场景的 RATE、TOTAL、CPU、MEM 等参数。

# ── W1~W8 参数定义 ──
# 格式: WORKLOAD_<ID>="RATE TOTAL CPU MEM GANG_SIZE DESCRIPTION"

declare -A WORKLOAD_RATE
declare -A WORKLOAD_TOTAL
declare -A WORKLOAD_CPU
declare -A WORKLOAD_MEM
declare -A WORKLOAD_GANG_SIZE
declare -A WORKLOAD_TYPE
declare -A WORKLOAD_DESC

# W1: 低负载稳态
WORKLOAD_RATE[w1]=100
WORKLOAD_TOTAL[w1]=10000
WORKLOAD_CPU[w1]=100
WORKLOAD_MEM[w1]=128
WORKLOAD_GANG_SIZE[w1]=0
WORKLOAD_TYPE[w1]="basic"
WORKLOAD_DESC[w1]="低负载稳态 (100 pods/s, 10K pods)"

# W2: 中负载稳态
WORKLOAD_RATE[w2]=500
WORKLOAD_TOTAL[w2]=50000
WORKLOAD_CPU[w2]=100
WORKLOAD_MEM[w2]=128
WORKLOAD_GANG_SIZE[w2]=0
WORKLOAD_TYPE[w2]="basic"
WORKLOAD_DESC[w2]="中负载稳态 (500 pods/s, 50K pods)"

# W3: 高负载稳态
WORKLOAD_RATE[w3]=1000
WORKLOAD_TOTAL[w3]=100000
WORKLOAD_CPU[w3]=100
WORKLOAD_MEM[w3]=128
WORKLOAD_GANG_SIZE[w3]=0
WORKLOAD_TYPE[w3]="basic"
WORKLOAD_DESC[w3]="高负载稳态 (1000 pods/s, 100K pods)"

# W4: 极限负载
WORKLOAD_RATE[w4]=2000
WORKLOAD_TOTAL[w4]=200000
WORKLOAD_CPU[w4]=100
WORKLOAD_MEM[w4]=128
WORKLOAD_GANG_SIZE[w4]=0
WORKLOAD_TYPE[w4]="basic"
WORKLOAD_DESC[w4]="极限负载 (2000 pods/s, 200K pods)"

# W5: 突发洪峰 (阶梯式: 0→2000→0)
WORKLOAD_RATE[w5]=2000
WORKLOAD_TOTAL[w5]=50000
WORKLOAD_CPU[w5]=100
WORKLOAD_MEM[w5]=128
WORKLOAD_GANG_SIZE[w5]=0
WORKLOAD_TYPE[w5]="burst"
WORKLOAD_DESC[w5]="突发洪峰 (0→2000→0 pods/s, 50K pods)"

# W6: Gang 调度
WORKLOAD_RATE[w6]=1000
WORKLOAD_TOTAL[w6]=10000
WORKLOAD_CPU[w6]=100
WORKLOAD_MEM[w6]=128
WORKLOAD_GANG_SIZE[w6]=5
WORKLOAD_TYPE[w6]="gang"
WORKLOAD_DESC[w6]="Gang 调度 (200 groups/s × 5 pods/group, 10K pods)"

# W7: 异构资源
WORKLOAD_RATE[w7]=500
WORKLOAD_TOTAL[w7]=50000
WORKLOAD_CPU[w7]=0     # 异构，由 create-pods.sh 处理
WORKLOAD_MEM[w7]=0
WORKLOAD_GANG_SIZE[w7]=0
WORKLOAD_TYPE[w7]="heterogeneous"
WORKLOAD_DESC[w7]="异构资源 (500 pods/s, 50K pods, 混合规格)"

# W8: 大规模集群
WORKLOAD_RATE[w8]=2000
WORKLOAD_TOTAL[w8]=800000
WORKLOAD_CPU[w8]=100
WORKLOAD_MEM[w8]=128
WORKLOAD_GANG_SIZE[w8]=0
WORKLOAD_TYPE[w8]="basic"
WORKLOAD_DESC[w8]="大规模集群参照 (2000 pods/s, 800K pods)"

# ── W7 异构资源混合比例 ──
# 30% 小规格: cpu:50m, mem:64Mi
# 40% 中规格: cpu:200m, mem:256Mi
# 20% 大规格: cpu:1000m, mem:1024Mi
# 10% 超大规格: cpu:4000m, mem:8192Mi
HETERO_RATIOS=(30 40 20 10)
HETERO_CPU=(50 200 1000 4000)
HETERO_MEM=(64 256 1024 8192)

# ── 获取负载参数 ──
# 用法: get_workload_param <workload_id> <param_name>
get_workload_param() {
  local wid="$1"
  local param="$2"

  case "$param" in
    rate)      echo "${WORKLOAD_RATE[$wid]:-0}" ;;
    total)     echo "${WORKLOAD_TOTAL[$wid]:-0}" ;;
    cpu)       echo "${WORKLOAD_CPU[$wid]:-100}" ;;
    mem)       echo "${WORKLOAD_MEM[$wid]:-128}" ;;
    gang_size) echo "${WORKLOAD_GANG_SIZE[$wid]:-0}" ;;
    type)      echo "${WORKLOAD_TYPE[$wid]:-basic}" ;;
    desc)      echo "${WORKLOAD_DESC[$wid]:-unknown}" ;;
    *)         echo "" ;;
  esac
}

# ── 列出所有负载场景 ──
list_workloads() {
  echo "负载场景矩阵:"
  echo "────────────────────────────────────────────────"
  for wid in w1 w2 w3 w4 w5 w6 w7 w8; do
    printf "  %-4s │ type=%-15s │ rate=%-5s │ total=%-7s │ %s\n" \
      "$wid" \
      "${WORKLOAD_TYPE[$wid]}" \
      "${WORKLOAD_RATE[$wid]}" \
      "${WORKLOAD_TOTAL[$wid]}" \
      "${WORKLOAD_DESC[$wid]}"
  done
  echo "────────────────────────────────────────────────"
}

# 如果直接执行此脚本，显示所有场景
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  list_workloads
fi
