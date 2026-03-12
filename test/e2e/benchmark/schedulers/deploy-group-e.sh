#!/usr/bin/env bash
# schedulers/deploy-group-e.sh — 部署组 E（Koordinator Scheduler）
#
# 配置: Koordinator v1.5.x (单实例)
# schedulerName: koord-scheduler

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

KOORDINATOR_VERSION="${KOORDINATOR_VERSION:-1.7.0}"

separator "部署组 E — Koordinator Scheduler"

# ── Step 1: 清理先前部署 ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# ── Step 2: 安装 Koordinator ──
log_step "Step 2: 安装 Koordinator v${KOORDINATOR_VERSION}"

# 添加 Helm repo（如尚未添加）
if ! helm repo list 2>/dev/null | grep -q "koordinator-sh"; then
  helm repo add koordinator-sh https://koordinator-sh.github.io/charts
fi
helm repo update koordinator-sh

# 安装 Koordinator（使用 --create-namespace 让 Helm 自行管理 namespace）

# 注意: KWOK 节点上无法运行容器，但 K8s 会把 Pod 调度上去
# - koordlet/device-daemon: 通过匹配不存在的标签完全禁用
# - scheduler/manager: 通过排除 fake 节点标签确保运行在真实节点上
# chart 的 DaemonSet 模板里 nodeAffinity 直接渲染到 affinity: 下，需要多嵌套一层
# chart 的 Deployment 模板里 nodeAffinity 正确渲染到 affinity.nodeAffinity: 下
KOORDINATOR_VALUES=$(mktemp)
cat > "${KOORDINATOR_VALUES}" <<'EOF'
koordlet:
  nodeAffinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: koordinator-skip
                operator: Exists
deviceDaemon:
  nodeAffinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: koordinator-skip
                operator: Exists
scheduler:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: fake.byted.org/node
              operator: DoesNotExist
manager:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: fake.byted.org/node
              operator: DoesNotExist
EOF

INSTALL_OUTPUT=$(helm install koordinator koordinator-sh/koordinator \
  -n "${KOORDINATOR_NAMESPACE}" \
  --create-namespace \
  -f "${KOORDINATOR_VALUES}" \
  --set scheduler.replicas=1 \
  --set manager.replicas=1 \
  --set descheduler.replicas=0 \
  --set scheduler.resources.requests.cpu=1 \
  --set scheduler.resources.requests.memory=1Gi \
  --wait \
  --timeout 5m \
  2>&1) || {
    log_warn "helm install 失败，错误信息:"
    echo "${INSTALL_OUTPUT}"
    log_warn "尝试 upgrade..."
    helm upgrade koordinator koordinator-sh/koordinator \
      -n "${KOORDINATOR_NAMESPACE}" \
      -f "${KOORDINATOR_VALUES}" \
      --set scheduler.replicas=1 \
      --set manager.replicas=1 \
      --set descheduler.replicas=0 \
      --set scheduler.resources.requests.cpu=1 \
      --set scheduler.resources.requests.memory=1Gi \
      --wait \
      --timeout 5m
  }
rm -f "${KOORDINATOR_VALUES}"

# ── Step 3: 等待组件就绪 ──
log_step "Step 3: 等待组件就绪"
sleep 10

kubectl wait --for=condition=Ready pod -l koord-app=koord-scheduler \
  -n "${KOORDINATOR_NAMESPACE}" --timeout="${WAIT_READY_TIMEOUT}s" 2>/dev/null || true

kubectl wait --for=condition=Ready pod -l koord-app=koord-manager \
  -n "${KOORDINATOR_NAMESPACE}" --timeout="${WAIT_READY_TIMEOUT}s" 2>/dev/null || true

# ── Step 4: 验证 ──
log_step "Step 4: 验证部署"
echo ""
kubectl get pods -n "${KOORDINATOR_NAMESPACE}" -o wide
echo ""

# 检查 CRDs
log_info "Koordinator CRDs:"
kubectl get crd 2>/dev/null | grep "koordinator\|slo.koordinator" || true

# ── Step 5: 切换 Prometheus 配置（kustomize overlay） ──
log_step "Step 5: 部署组 E 的 Prometheus 配置"
kubectl apply -k "${PROJECT_ROOT}/manifests/monitoring/overlays/group-e/"
kubectl rollout restart deployment prometheus -n "${PROMETHEUS_NAMESPACE}"
kubectl rollout status deployment prometheus -n "${PROMETHEUS_NAMESPACE}" --timeout=60s
wait_prometheus_ready 60 || log_warn "Prometheus 未就绪，手动检查"
verify_prometheus_targets

separator "组 E 部署完成"
log_info "架构: Koordinator Scheduler v${KOORDINATOR_VERSION} (单实例，无 koordlet)"
log_info "schedulerName: koord-scheduler"
log_info ""
log_info "注意: koordlet 已禁用（KWOK 节点无法运行 DaemonSet）"
log_info "      纯调度器模式测试，QoS 画像功能不可用"
