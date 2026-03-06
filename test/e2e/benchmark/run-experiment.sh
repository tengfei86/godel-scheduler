#!/usr/bin/env bash
# run-experiment.sh — 单次实验标准操作流程 (SOP)
#
# 用法:
#   ./run-experiment.sh <group> <scale> <workload> <run_id> [--setup-nodes] [--skip-collect]
#
# 参数:
#   group    - a|b|c|d|e          (调度器组)
#   scale    - s1|s2|s3|s4|s5     (集群节点规模: 100/1K/5K/10K/30K)
#   workload - w1|w2|w3|w4|w5|w6|w7|w8 (负载场景)
#   run_id   - 1|2|3              (重复次数)
#
# 可选标志:
#   --setup-nodes   自动创建/验证 KWOK 节点数量（默认假设已就绪）
#   --skip-collect  跳过 Prometheus 导出和分布快照采集
#
# 示例:
#   ./run-experiment.sh b s2 w3 2                  # 组B, 1000节点, W3负载, 第2次
#   ./run-experiment.sh a s3 w1 1 --setup-nodes    # 自动创建 5000 节点

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/workloads/workload-matrix.sh"

# ── 参数解析 ──
GROUP="${1:?用法: run-experiment.sh <group> <scale> <workload> <run_id> [--setup-nodes] [--skip-collect]}"
SCALE="${2:?缺少参数: scale (s1|s2|s3|s4|s5)}"
WORKLOAD="${3:?缺少参数: workload (w1|w2|...|w8)}"
RUN_ID="${4:?缺少参数: run_id (1|2|3)}"
shift 4

# ── 可选标志 ──
SETUP_NODES=false
SKIP_COLLECT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --setup-nodes)  SETUP_NODES=true; shift ;;
    --skip-collect) SKIP_COLLECT=true; shift ;;
    *)              log_error "未知参数: $1"; exit 1 ;;
  esac
done

# ── 验证参数 ──
if [[ ! "$GROUP" =~ ^[a-e]$ ]]; then
  log_error "无效的组标识: ${GROUP} (可选: a|b|c|d|e)"
  exit 1
fi

if [[ ! "$SCALE" =~ ^s[1-5]$ ]]; then
  log_error "无效的规模: ${SCALE} (可选: s1|s2|s3|s4|s5)"
  exit 1
fi

if [[ ! "$WORKLOAD" =~ ^w[1-8]$ ]]; then
  log_error "无效的负载场景: ${WORKLOAD} (可选: w1|w2|...|w8)"
  exit 1
fi

# ── 加载负载参数 ──
RATE=$(get_workload_param "$WORKLOAD" "rate")
TOTAL=$(get_workload_param "$WORKLOAD" "total")
CPU=$(get_workload_param "$WORKLOAD" "cpu")
MEM=$(get_workload_param "$WORKLOAD" "mem")
WTYPE=$(get_workload_param "$WORKLOAD" "type")
WDESC=$(get_workload_param "$WORKLOAD" "desc")
SCHED_NAME="${SCHEDULER_NAMES[$GROUP]}"
GROUP_LABEL="${GROUP_LABELS[$GROUP]}"
NODE_COUNT="${SCALE_NODES[$SCALE]}"

# ── 结果目录 (含 scale 维度) ──
EXP_RESULTS_DIR="${RESULTS_DIR}/${GROUP}/${SCALE}/${WORKLOAD}/run${RUN_ID}"
mkdir -p "$EXP_RESULTS_DIR"

separator "实验: 组=${GROUP} (${GROUP_LABEL}) | ${SCALE} (${NODE_COUNT}节点) | ${WORKLOAD} (${WDESC}) | Run #${RUN_ID}"

log_info "参数: rate=${RATE}, total=${TOTAL}, cpu=${CPU}m, mem=${MEM}Mi"
log_info "调度器: ${SCHED_NAME}"
log_info "集群规模: ${SCALE} (${NODE_COUNT} 节点)"
log_info "输出: ${EXP_RESULTS_DIR}"

# ═══════════════════════════════════════════════
# Step 0: API Server 连通性预检
# ═══════════════════════════════════════════════
log_step "Step 0: API Server 连通性预检"
check_api_server 10

# ═══════════════════════════════════════════════
# Step 1: 验证/调整 KWOK 节点数量
# ═══════════════════════════════════════════════
log_step "Step 1/11: 验证 KWOK 节点数量 (目标=${NODE_COUNT})"
ACTUAL_NODES=$(kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "当前 KWOK 节点: ${ACTUAL_NODES}, 期望: ${NODE_COUNT}"

if (( ACTUAL_NODES == NODE_COUNT )); then
  log_info "✓ 节点数量匹配"
elif [[ "$SETUP_NODES" == "true" ]]; then
  create_kwok_nodes "$NODE_COUNT"
else
  if (( ACTUAL_NODES > NODE_COUNT )); then
    log_error "节点过多 (${ACTUAL_NODES} > ${NODE_COUNT})，实验结果将不可信"
    log_error "请先清理节点或使用 --setup-nodes 自动调整"
    log_error "  手动清理: kubectl delete node -l fake.byted.org/node"
    log_error "  自动调整: $0 ${GROUP} ${SCALE} ${WORKLOAD} ${RUN_ID} --setup-nodes"
    exit 1
  else
    log_error "节点不足 (${ACTUAL_NODES} < ${NODE_COUNT})"
    log_error "请使用 --setup-nodes 自动创建，或手动创建节点"
    log_error "  自动创建: $0 ${GROUP} ${SCALE} ${WORKLOAD} ${RUN_ID} --setup-nodes"
    exit 1
  fi
fi

# ═══════════════════════════════════════════════
# Step 2: 清理上一轮测试环境
# ═══════════════════════════════════════════════
log_step "Step 2/11: 清理上一轮测试环境"
cleanup_bench "$BENCH_NAMESPACE"

# ═══════════════════════════════════════════════
# Step 3: 等待系统冷却
# ═══════════════════════════════════════════════
log_step "Step 3/11: 等待系统冷却 (${COOLDOWN_SECONDS}s)"
sleep "$COOLDOWN_SECONDS"

# ═══════════════════════════════════════════════
# Step 4: 验证调度器就绪
# ═══════════════════════════════════════════════
log_step "Step 4/11: 验证调度器就绪"
case "$GROUP" in
  a|b)
    kubectl get pods -n "${GODEL_NAMESPACE}" --no-headers 2>/dev/null
    ;;
  c)
    kubectl get pods -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null
    ;;
  d)
    kubectl get pods -n "${VOLCANO_NAMESPACE}" --no-headers 2>/dev/null
    ;;
  e)
    kubectl get pods -n "${KOORDINATOR_NAMESPACE}" --no-headers 2>/dev/null
    ;;
esac

# ═══════════════════════════════════════════════
# Step 5: 记录实验开始时间
# ═══════════════════════════════════════════════
log_step "Step 5/11: 记录实验开始时间"
START_TIME=$(date +%s)
START_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
log_info "开始时间: ${START_ISO} (ts=${START_TIME})"

# ═══════════════════════════════════════════════
# Step 6: 执行负载
# ═══════════════════════════════════════════════
log_step "Step 6/11: 执行负载 (${WDESC})"
bash "${SCRIPT_DIR}/workloads/create-pods.sh" \
  "$RATE" "$TOTAL" "$SCHED_NAME" "$CPU" "$MEM" "$WTYPE"

# ═══════════════════════════════════════════════
# Step 7: 轮询等待所有 Pod 调度完成
# ═══════════════════════════════════════════════
log_step "Step 7/11: 等待所有 Pod 调度完成"
wait_all_scheduled "$BENCH_NAMESPACE" "$WAIT_SCHEDULE_TIMEOUT"

# ═══════════════════════════════════════════════
# Step 8: 记录实验结束时间
# ═══════════════════════════════════════════════
log_step "Step 8/11: 记录实验结束时间"
END_TIME=$(date +%s)
END_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DURATION=$((END_TIME - START_TIME))
log_info "结束时间: ${END_ISO} (ts=${END_TIME})"
log_info "总耗时: $(format_duration $DURATION)"

# ═══════════════════════════════════════════════
# Step 9: 导出 Prometheus 数据
# ═══════════════════════════════════════════════
if [[ "$SKIP_COLLECT" == "true" ]]; then
  log_step "Step 9/11: 跳过 Prometheus 数据导出 (--skip-collect)"
else
  log_step "Step 9/11: 导出 Prometheus 数据"
  bash "${SCRIPT_DIR}/collect/export-prometheus.sh" \
    "$GROUP" "$START_TIME" "$END_TIME" "$EXP_RESULTS_DIR"
fi

# ═══════════════════════════════════════════════
# Step 10: 采集节点资源分布快照
# ═══════════════════════════════════════════════
if [[ "$SKIP_COLLECT" == "true" ]]; then
  log_step "Step 10/11: 跳过节点资源分布采集 (--skip-collect)"
else
  log_step "Step 10/11: 采集节点资源分布快照"
  bash "${SCRIPT_DIR}/collect/collect-utilization.sh" > "$EXP_RESULTS_DIR/utilization.csv"
fi

# ═══════════════════════════════════════════════
# Step 11: 采集 Pod 分布快照 + 写入元数据
# ═══════════════════════════════════════════════
log_step "Step 11/11: 采集 Pod 分布快照 & 元数据"
if [[ "$SKIP_COLLECT" != "true" ]]; then
  bash "${SCRIPT_DIR}/collect/collect-distribution.sh" > "$EXP_RESULTS_DIR/pod-distribution.csv"
fi

# 写入元数据
cat > "$EXP_RESULTS_DIR/metadata.txt" <<EOF
group=${GROUP}
group_label=${GROUP_LABEL}
scale=${SCALE}
node_count=${NODE_COUNT}
workload=${WORKLOAD}
workload_desc=${WDESC}
workload_type=${WTYPE}
run_id=${RUN_ID}
scheduler_name=${SCHED_NAME}
rate=${RATE}
total=${TOTAL}
cpu=${CPU}
mem=${MEM}
start_time=${START_TIME}
start_iso=${START_ISO}
end_time=${END_TIME}
end_iso=${END_ISO}
duration=${DURATION}
duration_human=$(format_duration $DURATION)
EOF

separator "实验完成"
log_info "组: ${GROUP} (${GROUP_LABEL})"
log_info "规模: ${SCALE} (${NODE_COUNT} 节点)"
log_info "负载: ${WORKLOAD} (${WDESC})"
log_info "Run: #${RUN_ID}"
log_info "耗时: $(format_duration $DURATION)"
log_info "结果: ${EXP_RESULTS_DIR}"
echo ""
ls -la "$EXP_RESULTS_DIR"
