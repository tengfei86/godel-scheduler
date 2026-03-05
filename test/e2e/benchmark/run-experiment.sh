#!/bin/bash
# run-experiment.sh — 单次实验标准操作流程 (SOP)
#
# 用法:
#   ./run-experiment.sh <group> <workload> <run_id>
#
# 参数:
#   group    - a|b|c|d|e
#   workload - w1|w2|w3|w4|w5|w6|w7|w8
#   run_id   - 1|2|3 (重复次数)
#
# 示例:
#   ./run-experiment.sh b w3 2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"
source "${SCRIPT_DIR}/workloads/workload-matrix.sh"

# ── 参数解析 ──
GROUP="${1:?用法: run-experiment.sh <group> <workload> <run_id>}"
WORKLOAD="${2:?缺少参数: workload (w1|w2|...|w8)}"
RUN_ID="${3:?缺少参数: run_id (1|2|3)}"

# ── 验证参数 ──
if [[ ! "$GROUP" =~ ^[a-e]$ ]]; then
  log_error "无效的组标识: ${GROUP} (可选: a|b|c|d|e)"
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

# ── 结果目录 ──
EXP_RESULTS_DIR="${RESULTS_DIR}/${GROUP}/${WORKLOAD}/run${RUN_ID}"
mkdir -p "$EXP_RESULTS_DIR"

separator "实验: 组=${GROUP} (${GROUP_LABEL}) | ${WORKLOAD} (${WDESC}) | Run #${RUN_ID}"

log_info "参数: rate=${RATE}, total=${TOTAL}, cpu=${CPU}m, mem=${MEM}Mi"
log_info "调度器: ${SCHED_NAME}"
log_info "输出: ${EXP_RESULTS_DIR}"

# ═══════════════════════════════════════════════
# Step 1: 清理上一轮测试环境
# ═══════════════════════════════════════════════
log_step "Step 1/10: 清理上一轮测试环境"
cleanup_bench "$BENCH_NAMESPACE"

# ═══════════════════════════════════════════════
# Step 2: 等待系统冷却
# ═══════════════════════════════════════════════
log_step "Step 2/10: 等待系统冷却 (${COOLDOWN_SECONDS}s)"
sleep "$COOLDOWN_SECONDS"

# ═══════════════════════════════════════════════
# Step 3: 验证调度器就绪
# ═══════════════════════════════════════════════
log_step "Step 3/10: 验证调度器就绪"
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
# Step 4: 记录实验开始时间
# ═══════════════════════════════════════════════
log_step "Step 4/10: 记录实验开始时间"
START_TIME=$(date +%s)
START_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
log_info "开始时间: ${START_ISO} (ts=${START_TIME})"

# ═══════════════════════════════════════════════
# Step 5: 执行负载
# ═══════════════════════════════════════════════
log_step "Step 5/10: 执行负载 (${WDESC})"
bash "${SCRIPT_DIR}/workloads/create-pods.sh" \
  "$RATE" "$TOTAL" "$SCHED_NAME" "$CPU" "$MEM" "$WTYPE"

# ═══════════════════════════════════════════════
# Step 6: 轮询等待所有 Pod 调度完成
# ═══════════════════════════════════════════════
log_step "Step 6/10: 等待所有 Pod 调度完成"
wait_all_scheduled "$BENCH_NAMESPACE" "$WAIT_SCHEDULE_TIMEOUT"

# ═══════════════════════════════════════════════
# Step 7: 记录实验结束时间
# ═══════════════════════════════════════════════
log_step "Step 7/10: 记录实验结束时间"
END_TIME=$(date +%s)
END_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DURATION=$((END_TIME - START_TIME))
log_info "结束时间: ${END_ISO} (ts=${END_TIME})"
log_info "总耗时: $(format_duration $DURATION)"

# ═══════════════════════════════════════════════
# Step 8: 导出 Prometheus 数据
# ═══════════════════════════════════════════════
log_step "Step 8/10: 导出 Prometheus 数据"
bash "${SCRIPT_DIR}/collect/export-prometheus.sh" \
  "$GROUP" "$START_TIME" "$END_TIME" "$EXP_RESULTS_DIR"

# ═══════════════════════════════════════════════
# Step 9: 采集节点资源分布快照
# ═══════════════════════════════════════════════
log_step "Step 9/10: 采集节点资源分布快照"
bash "${SCRIPT_DIR}/collect/collect-utilization.sh" > "$EXP_RESULTS_DIR/utilization.csv"

# ═══════════════════════════════════════════════
# Step 10: 采集 Pod 分布快照 + 写入元数据
# ═══════════════════════════════════════════════
log_step "Step 10/10: 采集 Pod 分布快照 & 元数据"
bash "${SCRIPT_DIR}/collect/collect-distribution.sh" > "$EXP_RESULTS_DIR/pod-distribution.csv"

# 写入元数据
cat > "$EXP_RESULTS_DIR/metadata.txt" <<EOF
group=${GROUP}
group_label=${GROUP_LABEL}
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
log_info "负载: ${WORKLOAD} (${WDESC})"
log_info "Run: #${RUN_ID}"
log_info "耗时: $(format_duration $DURATION)"
log_info "结果: ${EXP_RESULTS_DIR}"
echo ""
ls -la "$EXP_RESULTS_DIR"
