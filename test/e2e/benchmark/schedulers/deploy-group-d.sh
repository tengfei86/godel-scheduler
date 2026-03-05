#!/bin/bash
# schedulers/deploy-group-d.sh — 部署组 D（Volcano Scheduler）
#
# 配置: Volcano v1.9.x (单实例)
# schedulerName: volcano

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

VOLCANO_VERSION="${VOLCANO_VERSION:-1.9.0}"

separator "部署组 D — Volcano Scheduler"

# ── Step 1: 清理先前部署 ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# ── Step 2: 安装 Volcano ──
log_step "Step 2: 安装 Volcano v${VOLCANO_VERSION}"

# 添加 Helm repo（如尚未添加）
if ! helm repo list 2>/dev/null | grep -q "volcano-sh"; then
  helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
fi
helm repo update volcano-sh

# 安装 Volcano
kubectl create namespace "${VOLCANO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm install volcano volcano-sh/volcano \
  -n "${VOLCANO_NAMESPACE}" \
  --version "${VOLCANO_VERSION}" \
  --set scheduler.replicas=1 \
  --set controller.replicas=1 \
  --set scheduler.resources.requests.cpu=4 \
  --set scheduler.resources.requests.memory=8Gi \
  --set controller.resources.requests.cpu=2 \
  --set controller.resources.requests.memory=4Gi \
  --wait \
  --timeout 5m \
  2>/dev/null || {
    # 如果已存在，尝试 upgrade
    log_warn "helm install 失败，尝试 upgrade..."
    helm upgrade volcano volcano-sh/volcano \
      -n "${VOLCANO_NAMESPACE}" \
      --version "${VOLCANO_VERSION}" \
      --set scheduler.replicas=1 \
      --set controller.replicas=1 \
      --set scheduler.resources.requests.cpu=4 \
      --set scheduler.resources.requests.memory=8Gi \
      --set controller.resources.requests.cpu=2 \
      --set controller.resources.requests.memory=4Gi \
      --wait \
      --timeout 5m
  }

# ── Step 3: 等待组件就绪 ──
log_step "Step 3: 等待组件就绪"
sleep 10

kubectl wait --for=condition=Ready pod -l app=volcano-scheduler \
  -n "${VOLCANO_NAMESPACE}" --timeout="${WAIT_READY_TIMEOUT}s" 2>/dev/null || true

kubectl wait --for=condition=Ready pod -l app=volcano-controller-manager \
  -n "${VOLCANO_NAMESPACE}" --timeout="${WAIT_READY_TIMEOUT}s" 2>/dev/null || true

# ── Step 4: 验证 ──
log_step "Step 4: 验证部署"
echo ""
kubectl get pods -n "${VOLCANO_NAMESPACE}" -o wide
echo ""

# 检查 CRDs
log_info "Volcano CRDs:"
kubectl get crd 2>/dev/null | grep "volcano\|scheduling.volcano" || true

# ── Step 5: 确保 Prometheus 抓取目标正确 ──
log_step "Step 5: 验证 Prometheus 目标"
wait_prometheus_ready 30 || log_warn "Prometheus 未就绪，手动检查"

separator "组 D 部署完成"
log_info "架构: Volcano Scheduler v${VOLCANO_VERSION} (单实例)"
log_info "schedulerName: volcano"
log_info ""
log_info "注意: Volcano Pod 需要使用 schedulerName: volcano"
log_info "      Gang 调度需要创建 PodGroup CRD"
