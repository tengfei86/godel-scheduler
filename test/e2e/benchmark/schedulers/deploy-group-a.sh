#!/usr/bin/env bash
# schedulers/deploy-group-a.sh — 部署组 A（共享 Binder，原始 Gödel 架构）
#
# 配置: --enable-embedded-binder=false + 独立 Binder Deployment (replicas=1)
# schedulerName: godel-scheduler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

separator "部署组 A — 共享 Binder (Baseline)"

# ── Step 1: 清理先前部署 ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# ── Step 2: 部署 Gödel（共享 Binder） ──
log_step "Step 2: 部署 Gödel Scheduler (Shared Binder)"
kubectl apply -k "${MANIFESTS_BASE}"

# ── Step 3: 等待组件就绪 ──
log_step "Step 3: 等待组件就绪"
sleep 10

# 等待 Dispatcher
wait_deployment_ready "${GODEL_NAMESPACE}" "dispatcher" "${WAIT_READY_TIMEOUT}"

# 等待 Binder (replicas=1)
wait_deployment_ready "${GODEL_NAMESPACE}" "binder" "${WAIT_READY_TIMEOUT}"

# 等待 Scheduler 实例
for deploy in $(kubectl get deployment -n "${GODEL_NAMESPACE}" --no-headers 2>/dev/null | awk '{print $1}' | grep "^scheduler-"); do
  wait_deployment_ready "${GODEL_NAMESPACE}" "$deploy" "${WAIT_READY_TIMEOUT}"
done

# ── Step 4: 验证 ──
log_step "Step 4: 验证部署"
echo ""
kubectl get pods -n "${GODEL_NAMESPACE}" -o wide
echo ""

# 确认 Binder 独立运行
local_binder_count=$(kubectl get pods -n "${GODEL_NAMESPACE}" -l component=binder --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "Binder Pod 数量: ${local_binder_count} (预期: 1)"

if (( local_binder_count < 1 )); then
  log_error "Binder Pod 未就绪！"
  exit 1
fi

# ── Step 5: 切换 Prometheus 配置（kustomize overlay） ──
log_step "Step 5: 部署组 A 的 Prometheus 配置"
kubectl apply -k "${PROJECT_ROOT}/manifests/monitoring/overlays/group-a/"
wait_prometheus_ready 60 || log_warn "Prometheus 未就绪，手动检查"
verify_prometheus_targets

separator "组 A 部署完成"
log_info "架构: 共享 Binder (所有 Scheduler 共用 1 个 Binder)"
log_info "schedulerName: godel-scheduler"
show_node_partition
