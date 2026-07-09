#!/usr/bin/env bash
# schedulers/deploy-group-a.sh — 部署组 A（Gödel Scheduler，Baseline）
#
# 使用上游原始 godel-scheduler 二进制（godel-local:latest），
# 部署于 godel-system 命名空间，保持原始 godel 约定。
# schedulerName: godel-scheduler

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

separator "部署组 A — Gödel Scheduler (Baseline)"

# ── Step 1: 清理先前部署 ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# ── Step 2: 部署原始 Gödel Scheduler ──
log_step "Step 2: 部署 Gödel Scheduler (godel-local:latest)"
ensure_image_loaded "${GODEL_IMAGE}"
kubectl apply -k "${MANIFESTS_GROUP_A}"

# ── 多实例部署 ──
if (( SCHEDULER_INSTANCES > 1 )); then
  log_step "Step 2b: 部署 ${SCHEDULER_INSTANCES} 个 Scheduler 实例"
  # 多实例需手动 scale（原始 godel 在 godel-system 命名空间）
  for i in $(seq 1 $((SCHEDULER_INSTANCES - 1))); do
    local_name="scheduler-${i}"
    kubectl -n "${GODEL_NAMESPACE}" get deployment scheduler -o json | \
      jq --arg name "$local_name" '.metadata.name = $name | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .status)' | \
      kubectl apply -f -
  done
fi

# 对齐各组件资源，确保与其他调度器组公平对比
set_deploy_resources() {
  local deploy="$1" req_cpu="$2" req_mem="$3" lim_cpu="$4" lim_mem="$5"
  if kubectl get deployment "$deploy" -n "${GODEL_NAMESPACE}" >/dev/null 2>&1; then
    kubectl set resources deployment/"$deploy" \
      -n "${GODEL_NAMESPACE}" \
      --containers='*' \
      --requests="cpu=${req_cpu},memory=${req_mem}" \
      --limits="cpu=${lim_cpu},memory=${lim_mem}" >/dev/null
  fi
}

set_deploy_resources "binder" "${BENCH_BINDER_REQ_CPU}" "${BENCH_BINDER_REQ_MEM}" "${BENCH_BINDER_LIM_CPU}" "${BENCH_BINDER_LIM_MEM}"
set_deploy_resources "dispatcher" "${BENCH_DISPATCHER_REQ_CPU}" "${BENCH_DISPATCHER_REQ_MEM}" "${BENCH_DISPATCHER_LIM_CPU}" "${BENCH_DISPATCHER_LIM_MEM}"
set_deploy_resources "scheduler" "${BENCH_SCHED_REQ_CPU}" "${BENCH_SCHED_REQ_MEM}" "${BENCH_SCHED_LIM_CPU}" "${BENCH_SCHED_LIM_MEM}"
set_deploy_resources "controller-manager" "${BENCH_SCHED_REQ_CPU}" "${BENCH_SCHED_REQ_MEM}" "${BENCH_SCHED_LIM_CPU}" "${BENCH_SCHED_LIM_MEM}"

# ── Step 3: 等待组件就绪 ──
log_step "Step 3: 等待组件就绪"
sleep 10

# 等待 Dispatcher
wait_deployment_ready "${GODEL_NAMESPACE}" "dispatcher" "${WAIT_READY_TIMEOUT}"

# 等待 Binder (replicas=1)
wait_deployment_ready "${GODEL_NAMESPACE}" "binder" "${WAIT_READY_TIMEOUT}"

# 等待 Scheduler 实例
if (( SCHEDULER_INSTANCES > 1 )); then
  for i in $(seq 0 $((SCHEDULER_INSTANCES - 1))); do
    wait_deployment_ready "${GODEL_NAMESPACE}" "scheduler-${i}" "${WAIT_READY_TIMEOUT}"
  done
else
  wait_deployment_ready "${GODEL_NAMESPACE}" "scheduler" "${WAIT_READY_TIMEOUT}"
fi

# ── Step 4: 验证 ──
log_step "Step 4: 验证部署"
echo ""
kubectl get pods -n "${GODEL_NAMESPACE}" -o wide
echo ""

# 确认 Binder 独立运行
local_binder_count=$(kubectl get pods -n "${GODEL_NAMESPACE}" -l app=binder --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "Binder Pod 数量: ${local_binder_count} (预期: 1)"

if (( local_binder_count < 1 )); then
  log_error "Binder Pod 未就绪！"
  exit 1
fi

# ── Step 5: 切换 Prometheus 配置（kustomize overlay） ──
log_step "Step 5: 部署组 A 的 Prometheus 配置"
kubectl apply -k "${PROJECT_ROOT}/manifests/monitoring/overlays/godel-scheduler/"
kubectl rollout restart deployment prometheus -n "${PROMETHEUS_NAMESPACE}"
kubectl rollout status deployment prometheus -n "${PROMETHEUS_NAMESPACE}" --timeout=600s
wait_prometheus_ready 60 || log_warn "Prometheus 未就绪，手动检查"
verify_prometheus_targets

separator "组 A 部署完成"
log_info "架构: Gödel Scheduler (Baseline)"
log_info "镜像: ${GODEL_IMAGE}"
log_info "命名空间: ${GODEL_NAMESPACE}"
log_info "schedulerName: godel-scheduler"
show_node_partition
