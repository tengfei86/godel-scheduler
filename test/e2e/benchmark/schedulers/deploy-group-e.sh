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

KOORDINATOR_VERSION="${KOORDINATOR_VERSION:-1.9.0}"

separator "部署组 E — Koordinator Scheduler"

# ── Step 1: 清理先前部署 ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# 额外等待：确保 webhook 和 namespace 完全清除后再安装
log_info "等待 10s 确保资源完全清理..."
sleep 10

# ── Step 2: 安装 Koordinator ──
log_step "Step 2: 安装 Koordinator v${KOORDINATOR_VERSION}"

# 添加 Helm repo（如尚未添加）
if ! helm repo list 2>/dev/null | grep -q "koordinator-sh"; then
  helm repo add koordinator-sh https://koordinator-sh.github.io/charts
fi
helm repo update koordinator-sh

# 安装 Koordinator（幂等）：
# - namespace 处于 Terminating 时先等待删除完成
# - namespace 已存在时补齐 Helm ownership 元数据，避免 chart 包含 Namespace 资源时安装失败
# - 使用 helm upgrade --install 支持重复执行

if kubectl get namespace "${KOORDINATOR_NAMESPACE}" >/dev/null 2>&1; then
  ns_phase=$(kubectl get namespace "${KOORDINATOR_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "${ns_phase}" == "Terminating" ]]; then
    log_warn "namespace ${KOORDINATOR_NAMESPACE} 正在 Terminating，等待删除完成..."
    kubectl wait --for=delete namespace/"${KOORDINATOR_NAMESPACE}" --timeout=180s 2>/dev/null || true
  fi
fi

if ! kubectl get namespace "${KOORDINATOR_NAMESPACE}" >/dev/null 2>&1; then
  kubectl create namespace "${KOORDINATOR_NAMESPACE}" >/dev/null
fi

kubectl label namespace "${KOORDINATOR_NAMESPACE}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
kubectl annotate namespace "${KOORDINATOR_NAMESPACE}" meta.helm.sh/release-name=koordinator --overwrite >/dev/null 2>&1 || true
kubectl annotate namespace "${KOORDINATOR_NAMESPACE}" meta.helm.sh/release-namespace="${KOORDINATOR_NAMESPACE}" --overwrite >/dev/null 2>&1 || true

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

# 确保没有残留 webhook 拦截 API 请求（防止 context deadline exceeded）
log_info "清理可能残留的 Koordinator webhook..."
kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep -i 'koordinator\|koord' | xargs -r kubectl delete 2>/dev/null || true
kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep -i 'koordinator\|koord' | xargs -r kubectl delete 2>/dev/null || true

# 安装 Koordinator（带重试 — webhook/CRD 注册可能需要多轮尝试）
HELM_MAX_RETRIES=3
HELM_RETRY=0
INSTALL_OK=false

while (( HELM_RETRY < HELM_MAX_RETRIES )); do
  HELM_RETRY=$((HELM_RETRY + 1))
  log_info "Helm install 尝试 ${HELM_RETRY}/${HELM_MAX_RETRIES}..."

  INSTALL_OUTPUT=$(helm upgrade --install koordinator koordinator-sh/koordinator \
    -n "${KOORDINATOR_NAMESPACE}" \
    -f "${KOORDINATOR_VALUES}" \
    --set scheduler.replicas=1 \
    --set manager.replicas=1 \
    --set descheduler.replicas=0 \
    --set scheduler.resources.requests.cpu=${BENCH_SCHED_REQ_CPU} \
    --set scheduler.resources.requests.memory=${BENCH_SCHED_REQ_MEM} \
    --set scheduler.resources.limits.cpu=${BENCH_SCHED_LIM_CPU} \
    --set scheduler.resources.limits.memory=${BENCH_SCHED_LIM_MEM} \
    --set manager.resources.requests.cpu=${BENCH_SCHED_REQ_CPU} \
    --set manager.resources.requests.memory=${BENCH_SCHED_REQ_MEM} \
    --set manager.resources.limits.cpu=${BENCH_SCHED_LIM_CPU} \
    --set manager.resources.limits.memory=${BENCH_SCHED_LIM_MEM} \
    --wait \
    --timeout 10m \
    2>&1) && {
      INSTALL_OK=true
      break
    }

  log_warn "Helm install 尝试 ${HELM_RETRY} 失败:"
  echo "${INSTALL_OUTPUT}" | tail -5

  if (( HELM_RETRY < HELM_MAX_RETRIES )); then
    # 安装失败后清理残留 webhook，防止下次尝试被拦截
    log_info "清理失败安装残留的 webhook..."
    kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep -i 'koordinator\|koord' | xargs -r kubectl delete 2>/dev/null || true
    kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep -i 'koordinator\|koord' | xargs -r kubectl delete 2>/dev/null || true
    sleep 15
  fi
done

if [[ "$INSTALL_OK" != "true" ]]; then
  log_error "Helm install 在 ${HELM_MAX_RETRIES} 次尝试后仍失败"
  log_error "最后一次错误:"
  echo "${INSTALL_OUTPUT}"
  log_error ""
  log_error "调试步骤:"
  log_error "  1. kubectl get pods -n ${KOORDINATOR_NAMESPACE}"
  log_error "  2. kubectl get mutatingwebhookconfiguration,validatingwebhookconfiguration | grep koord"
  log_error "  3. kubectl describe pod -n ${KOORDINATOR_NAMESPACE} -l koord-app=koord-manager"
  exit 1
fi
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
kubectl rollout status deployment prometheus -n "${PROMETHEUS_NAMESPACE}" --timeout=600s
wait_prometheus_ready 60 || log_warn "Prometheus 未就绪，手动检查"
verify_prometheus_targets

separator "组 E 部署完成"
log_info "架构: Koordinator Scheduler v${KOORDINATOR_VERSION} (单实例，无 koordlet)"
log_info "schedulerName: koord-scheduler"
log_info ""
log_info "注意: koordlet 已禁用（KWOK 节点无法运行 DaemonSet）"
log_info "      纯调度器模式测试，QoS 画像功能不可用"
