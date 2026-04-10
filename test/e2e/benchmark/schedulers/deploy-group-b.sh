#!/usr/bin/env bash
# schedulers/deploy-group-b.sh — 部署组 B（独立 Binder，论文提出的架构）
#
# 配置: --enable-embedded-binder=true + Binder Deployment replicas=0
# schedulerName: eno-scheduler

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

# ── 可选参数 ──
SCHEDULER_INSTANCES=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --instances) SCHEDULER_INSTANCES="$2"; shift 2 ;;
    *)           log_error "未知参数: $1"; exit 1 ;;
  esac
done

separator "部署组 B — 独立 Binder (Proposed)"

# ── Step 1: 清理先前部署 ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# ── Step 2: 部署 Gödel（独立 Binder） ──
log_step "Step 2: 部署 Gödel Scheduler (Embedded Binder)"
ensure_image_loaded "${ENO_IMAGE}"
kubectl apply -k "${MANIFESTS_EMBEDDED}"

# ── 多实例部署 ──
if (( SCHEDULER_INSTANCES > 1 )); then
  log_step "Step 2b: 部署 ${SCHEDULER_INSTANCES} 个 Scheduler 实例 (内嵌 Binder)"
  bash "${SCRIPT_DIR}/schedulers/scale-schedulers.sh" "$SCHEDULER_INSTANCES" --embedded-binder
fi

# 对齐各组件资源，确保与其他调度器组公平对比
set_deploy_resources() {
  local deploy="$1" req_cpu="$2" req_mem="$3" lim_cpu="$4" lim_mem="$5"
  if kubectl get deployment "$deploy" -n "${ENO_NAMESPACE}" >/dev/null 2>&1; then
    kubectl set resources deployment/"$deploy" \
      -n "${ENO_NAMESPACE}" \
      --containers='*' \
      --requests="cpu=${req_cpu},memory=${req_mem}" \
      --limits="cpu=${lim_cpu},memory=${lim_mem}" >/dev/null
  fi
}

set_deploy_resources "binder" "${BENCH_BINDER_REQ_CPU}" "${BENCH_BINDER_REQ_MEM}" "${BENCH_BINDER_LIM_CPU}" "${BENCH_BINDER_LIM_MEM}"
set_deploy_resources "dispatcher" "${BENCH_DISPATCHER_REQ_CPU}" "${BENCH_DISPATCHER_REQ_MEM}" "${BENCH_DISPATCHER_LIM_CPU}" "${BENCH_DISPATCHER_LIM_MEM}"
if (( SCHEDULER_INSTANCES <= 1 )); then
  set_deploy_resources "scheduler" "${BENCH_SCHED_REQ_CPU}" "${BENCH_SCHED_REQ_MEM}" "${BENCH_SCHED_LIM_CPU}" "${BENCH_SCHED_LIM_MEM}"
fi
set_deploy_resources "controller-manager" "${BENCH_SCHED_REQ_CPU}" "${BENCH_SCHED_REQ_MEM}" "${BENCH_SCHED_LIM_CPU}" "${BENCH_SCHED_LIM_MEM}"

# ── Step 3: 等待组件就绪 ──
log_step "Step 3: 等待组件就绪"
sleep 10

# 等待 Dispatcher
wait_deployment_ready "${ENO_NAMESPACE}" "dispatcher" "${WAIT_READY_TIMEOUT}"

# Binder replicas=0，不需要等待

# 等待 Scheduler 实例（每个内嵌了 Binder）
if (( SCHEDULER_INSTANCES > 1 )); then
  for i in $(seq 0 $((SCHEDULER_INSTANCES - 1))); do
    wait_deployment_ready "${ENO_NAMESPACE}" "scheduler-${i}" "${WAIT_READY_TIMEOUT}"
  done
else
  for deploy in $(kubectl get deployment -n "${ENO_NAMESPACE}" --no-headers 2>/dev/null | awk '{print $1}' | grep "^scheduler"); do
    wait_deployment_ready "${ENO_NAMESPACE}" "$deploy" "${WAIT_READY_TIMEOUT}"
  done
fi

# ── Step 4: 验证 ──
log_step "Step 4: 验证部署"
echo ""
kubectl get pods -n "${ENO_NAMESPACE}" -o wide
echo ""

# 确认独立 Binder 未运行
local_binder_count=$(kubectl get pods -n "${ENO_NAMESPACE}" -l component=binder --no-headers 2>/dev/null | grep -c "Running" || true)
log_info "独立 Binder Pod 数量: ${local_binder_count} (预期: 0)"

if (( local_binder_count > 0 )); then
  log_warn "发现运行中的独立 Binder Pod，这不符合组 B 的配置！"
fi

# 验证 Scheduler 中启用了 embedded binder
scheduler_pod=""
scheduler_pod=$(kubectl get pods -n "${ENO_NAMESPACE}" -l app=eno-scheduler --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [[ -n "$scheduler_pod" ]]; then
  if kubectl logs "$scheduler_pod" -n "${ENO_NAMESPACE}" --tail=20 2>/dev/null | grep -qi "embedded.*binder\|binder.*embedded"; then
    log_info "✓ Embedded Binder 已在 Scheduler 中启用"
  else
    log_info "检查 Scheduler 日志以确认 Embedded Binder 状态..."
  fi
fi

# ── Step 5: 切换 Prometheus 配置（kustomize overlay） ──
log_step "Step 5: 部署组 B 的 Prometheus 配置"
kubectl apply -k "${PROJECT_ROOT}/manifests/monitoring/overlays/group-b/"
kubectl rollout restart deployment prometheus -n "${PROMETHEUS_NAMESPACE}"
kubectl rollout status deployment prometheus -n "${PROMETHEUS_NAMESPACE}" --timeout=600s
wait_prometheus_ready 60 || log_warn "Prometheus 未就绪，手动检查"
verify_prometheus_targets

separator "组 B 部署完成"
log_info "架构: 独立 Binder (每个 Scheduler 内嵌独立 Binder)"
log_info "schedulerName: eno-scheduler"
show_node_partition
