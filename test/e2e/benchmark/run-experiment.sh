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
# 集群规模说明:
#   s1 -    100 节点  (小规模基线, 1 Scheduler)
#   s2 -  1,000 节点  (中等规模,   3 Scheduler)
#   s3 -  5,000 节点  (大规模,     3 Scheduler)
#   s4 - 10,000 节点  (超大规模,   3 Scheduler)
#   s5 - 30,000 节点  (极限规模,   3 Scheduler)
#
# 负载场景说明:
#   w1 - 低负载稳态       100 pods/s,  10K pods, cpu:100m/mem:128Mi
#   w2 - 中负载稳态       500 pods/s,  50K pods, cpu:100m/mem:128Mi
#   w3 - 高负载稳态     1,000 pods/s, 100K pods, cpu:100m/mem:128Mi
#   w4 - 极限负载       2,000 pods/s, 200K pods, cpu:100m/mem:128Mi
#   w5 - 突发洪峰   0→2000→0 pods/s,  50K pods, cpu:100m/mem:128Mi
#   w6 - Gang 调度   200 groups/s × 5 pods/group, 10K pods
#   w7 - 异构资源       500 pods/s,  50K pods, 混合规格(30%小+40%中+20%大+10%超大)
#   w8 - 大规模集群   2,000 pods/s, 800K pods, cpu:100m/mem:128Mi
#
# 可选标志:
#   --setup-nodes   自动创建/验证 KWOK 节点数量（默认假设已就绪）
#   --skip-collect  跳过 Prometheus 导出和分布快照采集
#
# 示例:
#   ./run-experiment.sh b s2 w2 1                  # 组B, 1000节点, W3负载, 第2次
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
SCHEDULER_INSTANCES=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --setup-nodes)  SETUP_NODES=true; shift ;;
    --skip-collect) SKIP_COLLECT=true; shift ;;
    --instances)    SCHEDULER_INSTANCES="$2"; shift 2 ;;
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

# ── 结果目录 (含 scale 和 instances 维度) ──
if [[ -n "$SCHEDULER_INSTANCES" ]]; then
  EXP_RESULTS_DIR="${RESULTS_DIR}/${GROUP}/${SCALE}/${WORKLOAD}/inst${SCHEDULER_INSTANCES}/run${RUN_ID}"
else
  EXP_RESULTS_DIR="${RESULTS_DIR}/${GROUP}/${SCALE}/${WORKLOAD}/run${RUN_ID}"
fi
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
log_step "Step 1/12: 验证 KWOK 节点数量 (目标=${NODE_COUNT})"
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
log_step "Step 2/12: 清理上一轮测试环境"
cleanup_bench "$BENCH_NAMESPACE"

# ── etcd 压缩：防止 "database space exceeded" ──
log_info "  压缩 etcd 历史版本..."
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$ETCD_POD" ]]; then
  ETCD_EXEC="kubectl exec -n kube-system ${ETCD_POD} -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
  CURRENT_REV=$(eval $ETCD_EXEC endpoint status --write-out=json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])" 2>/dev/null || true)
  if [[ -n "$CURRENT_REV" ]]; then
    eval $ETCD_EXEC compact "$CURRENT_REV" 2>/dev/null || true
    eval $ETCD_EXEC defrag 2>/dev/null || true
    DB_SIZE=$(eval $ETCD_EXEC endpoint status --write-out=json 2>/dev/null \
      | python3 -c "import sys,json; s=json.load(sys.stdin)[0]['Status']; print(f\"DB={s['dbSize']//1048576}MB InUse={s['dbSizeInUse']//1048576}MB\")" 2>/dev/null || echo "unknown")
    log_info "  ✓ etcd 压缩完成 (${DB_SIZE})"
  else
    log_warn "  跳过 etcd 压缩（无法获取 revision）"
  fi
else
  log_warn "  跳过 etcd 压缩（未找到 etcd Pod）"
fi

# ═══════════════════════════════════════════════
# Step 3/12: 重启 API Server (清理连接积压)
# ═══════════════════════════════════════════════
log_step "Step 3/12: 重启 API Server"
restart_apiserver

# ═══════════════════════════════════════════════
# Step 4/12: 等待系统冷却
# ═══════════════════════════════════════════════
log_step "Step 4/12: 等待系统冷却 (${COOLDOWN_SECONDS}s)"
sleep "$COOLDOWN_SECONDS"

# ═══════════════════════════════════════════════
# Step 5/12: 验证调度器就绪
# ═══════════════════════════════════════════════
log_step "Step 5/12: 验证调度器就绪"
verify_scheduler_ready() {
  local ns="$1" label="$2" desc="$3" name_prefix_regex="${4:-}"
  local running
  running=$(kubectl get pods -n "$ns" -l "$label" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

  # 某些部署里调度器 Pod 可能缺少预期 label，这里按 Pod 名前缀做兜底，避免误报未部署。
  if (( running == 0 )) && [[ -n "$name_prefix_regex" ]]; then
    running=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null \
      | awk '{print $1}' | grep -Ec "$name_prefix_regex" || true)
  fi

  if (( running == 0 )); then
    log_error "${desc} 未部署或未就绪 (namespace=${ns})"
    log_error "请先运行: bash schedulers/deploy-group-${GROUP}.sh"
    exit 1
  fi
  kubectl get pods -n "$ns" --no-headers 2>/dev/null
  log_info "✓ ${desc} 就绪 (${running} Running)"
}

case "$GROUP" in
  a)
    verify_scheduler_ready "${GODEL_NAMESPACE}" "app=godel-scheduler" "Gödel Scheduler (Original)" '^scheduler(-|$)'
    ;;
  b)
    verify_scheduler_ready "${ENO_NAMESPACE}" "app=eno-scheduler" "Eno Scheduler (Embedded Binder)" '^scheduler(-|$)'
    ;;
  c)
    verify_scheduler_ready "kube-system" "component=kube-scheduler" "kube-scheduler" '^kube-scheduler(-|$)'
    ;;
  d)
    verify_scheduler_ready "${VOLCANO_NAMESPACE}" "app=volcano-scheduler" "Volcano Scheduler" '^volcano-scheduler(-|$)'
    ;;
  e)
    verify_scheduler_ready "${KOORDINATOR_NAMESPACE}" "koord-app=koord-scheduler" "Koordinator Scheduler" '^koord-scheduler(-|$)'
    ;;
esac

# ═══════════════════════════════════════════════
# Step 6: 记录实验开始时间
# ═══════════════════════════════════════════════
log_step "Step 6/12: 记录实验开始时间"
START_TIME=$(date +%s)
START_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
log_info "开始时间: ${START_ISO} (ts=${START_TIME})"

# ═══════════════════════════════════════════════
# Step 7: 执行负载
# ═══════════════════════════════════════════════
log_step "Step 7/12: 执行负载 (${WDESC})"
bash "${SCRIPT_DIR}/workloads/create-pods.sh" \
  "$RATE" "$TOTAL" "$SCHED_NAME" "$CPU" "$MEM" "$WTYPE"

# ═══════════════════════════════════════════════
# Step 8: 轮询等待所有 Pod 调度完成
# ═══════════════════════════════════════════════
log_step "Step 8/12: 等待所有 Pod 调度完成"
wait_all_scheduled "$BENCH_NAMESPACE" "$WAIT_SCHEDULE_TIMEOUT"

# ═══════════════════════════════════════════════
# Step 9: 记录实验结束时间
# ═══════════════════════════════════════════════
log_step "Step 9/12: 记录实验结束时间"
END_TIME=$(date +%s)
END_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DURATION=$((END_TIME - START_TIME))
log_info "结束时间: ${END_ISO} (ts=${END_TIME})"
log_info "总耗时: $(format_duration $DURATION)"

# ═══════════════════════════════════════════════
# Step 10: 导出 Prometheus 数据
# ═══════════════════════════════════════════════
if [[ "$SKIP_COLLECT" == "true" ]]; then
  log_step "Step 10/12: 跳过 Prometheus 数据导出 (--skip-collect)"
else
  log_step "Step 10/12: 导出 Prometheus 数据"
  bash "${SCRIPT_DIR}/collect/export-prometheus.sh" \
    "$GROUP" "$START_TIME" "$END_TIME" "$EXP_RESULTS_DIR"
fi

# ═══════════════════════════════════════════════
# Step 11: 采集节点资源分布快照
# ═══════════════════════════════════════════════
if [[ "$SKIP_COLLECT" == "true" ]]; then
  log_step "Step 11/12: 跳过节点资源分布采集 (--skip-collect)"
else
  log_step "Step 11/12: 采集节点资源分布快照"
  bash "${SCRIPT_DIR}/collect/collect-utilization.sh" > "$EXP_RESULTS_DIR/utilization.csv"
fi

# ═══════════════════════════════════════════════
# Step 12: 采集 Pod 分布快照 + 写入元数据
# ═══════════════════════════════════════════════
log_step "Step 12/12: 采集 Pod 分布快照 & 元数据"
if [[ "$SKIP_COLLECT" != "true" ]]; then
  ANNO_DOMAIN="${ANNOTATION_DOMAINS[$GROUP]:-eno.io}"
  bash "${SCRIPT_DIR}/collect/collect-distribution.sh" "$ANNO_DOMAIN" > "$EXP_RESULTS_DIR/pod-distribution.csv"
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
scheduler_instances=${SCHEDULER_INSTANCES:-1}
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
