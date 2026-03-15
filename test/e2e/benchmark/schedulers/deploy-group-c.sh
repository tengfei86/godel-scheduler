#!/usr/bin/env bash
# schedulers/deploy-group-c.sh — 部署组 C（kube-scheduler，原生 K8s 调度器）
#
# 配置: 禁用 Gödel，使用 kind 自带的 kube-scheduler
# schedulerName: default-scheduler

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

separator "部署组 C — kube-scheduler (Reference)"

# ── Step 1: 清理先前部署（卸载 Gödel） ──
log_step "Step 1: 清理先前的调度器部署"
bash "${SCRIPT_DIR}/schedulers/teardown.sh"

# ── Step 2: 确认 kube-scheduler 运行 ──
log_step "Step 2: 确认 kube-scheduler 运行"

# kind 集群自带 kube-scheduler，只需确保其正常运行
if kubectl get pods -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null | grep -q "Running"; then
  log_info "✓ kube-scheduler 正在运行"
else
  log_warn "kube-scheduler 未检测到，等待恢复..."
  sleep 30
  if kubectl get pods -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null | grep -q "Running"; then
    log_info "✓ kube-scheduler 已恢复"
  else
    log_error "kube-scheduler 仍未运行，请检查集群状态"
    exit 1
  fi
fi

# ── Step 3: 调整 kube-scheduler 参数（QPS/Burst/LogLevel） ──
log_step "Step 3: 调整 kube-scheduler 参数"
local_container="${KIND_CLUSTER_NAME}-control-plane"

# 注入 QPS 和 Burst 参数，修改 bind-address 并统一资源配额（用于公平对比）
if ! docker exec "$local_container" bash -c "
  sched_manifest=/etc/kubernetes/manifests/kube-scheduler.yaml

  if ! grep -q 'kube-api-qps' /etc/kubernetes/manifests/kube-scheduler.yaml; then
    sed -i '/- kube-scheduler/a\\    - --kube-api-qps=${SCHEDULER_QPS}' /etc/kubernetes/manifests/kube-scheduler.yaml
    sed -i '/- kube-scheduler/a\\    - --kube-api-burst=${SCHEDULER_BURST}' /etc/kubernetes/manifests/kube-scheduler.yaml
    sed -i '/- kube-scheduler/a\\    - --v=${LOG_LEVEL}' /etc/kubernetes/manifests/kube-scheduler.yaml
  fi

  # 先保证 kubeadm 官方 kubeconfig 路径存在，避免 kube-scheduler 启动报错。
  # 注意：这里必须写入“真实文件”，避免 hostPath(type=File) 对软链接兼容问题。
  if [[ ! -f /etc/kubernetes/scheduler.conf ]]; then
    src_conf=""
    for c in /etc/kubernetes/kube-scheduler.conf /etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf; do
      if [[ -f "\$c" ]]; then
        src_conf="\$c"
        break
      fi
    done

    if [[ -z "\$src_conf" ]]; then
      src_conf=$(find /etc/kubernetes -maxdepth 2 -type f -name '*scheduler*.conf' 2>/dev/null | head -1 || true)
    fi

    if [[ -n "\$src_conf" ]]; then
      cp -Lf "\$src_conf" /etc/kubernetes/scheduler.conf
      chmod 600 /etc/kubernetes/scheduler.conf || true
    else
      echo '[group-c] 缺少 /etc/kubernetes/scheduler.conf 且无可用回退文件' >&2
      ls -l /etc/kubernetes/*.conf 2>/dev/null || true
      exit 1
    fi
  fi

  # 诊断输出：确认 kubeconfig 文件存在。
  ls -l /etc/kubernetes/scheduler.conf /etc/kubernetes/kube-scheduler.conf 2>/dev/null || true

  # 统一 kube-scheduler static pod 的资源配额（来自 config.sh）
  if grep -q '^[[:space:]]*resources:' \"\$sched_manifest\"; then
    sed -i '/^[[:space:]]*resources:/,/^[[:space:]]*livenessProbe:/d' \"\$sched_manifest\"
  fi
  sed -i '/^[[:space:]]*livenessProbe:/i\\    resources:\\n      requests:\\n        cpu: \"${BENCH_SCHED_REQ_CPU}\"\\n        memory: ${BENCH_SCHED_REQ_MEM}\\n      limits:\\n        cpu: \"${BENCH_SCHED_LIM_CPU}\"\\n        memory: ${BENCH_SCHED_LIM_MEM}' \"\$sched_manifest\"

  # 开放 bind-address 使 Prometheus Pod 可以抓取 metrics
  sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-scheduler.yaml
"; then
  log_error "调整 kube-scheduler 参数失败，请检查 control-plane 容器日志"
  exit 1
fi

sleep 20
log_info "等待 kube-scheduler 重启完成..."
kubectl wait --for=condition=Ready node --all --timeout=120s 2>/dev/null || true

# ── Step 4: 验证 ──
log_step "Step 4: 验证部署"
echo ""
kubectl get pods -n kube-system -l component=kube-scheduler -o wide
echo ""

# 确认 Gödel 已卸载
if kubectl get namespace "${GODEL_NAMESPACE}" &>/dev/null; then
  local_godel_running=$(kubectl get pods -n "${GODEL_NAMESPACE}" --no-headers 2>/dev/null | grep -c "Running" || true)
  if (( local_godel_running > 0 )); then
    log_warn "Gödel 仍有 ${local_godel_running} 个运行中的 Pod，可能影响测试"
  fi
fi

# ── Step 5: 切换 Prometheus 配置（kustomize overlay） ──
log_step "Step 5: 部署组 C 的 Prometheus 配置"
kubectl apply -k "${PROJECT_ROOT}/manifests/monitoring/overlays/group-c/"
kubectl rollout restart deployment prometheus -n "${PROMETHEUS_NAMESPACE}"
kubectl rollout status deployment prometheus -n "${PROMETHEUS_NAMESPACE}" --timeout=60s
wait_prometheus_ready 60 || log_warn "Prometheus 未就绪，手动检查"
verify_prometheus_targets

separator "组 C 部署完成"
log_info "架构: kube-scheduler (原生 K8s 单实例调度器)"
log_info "schedulerName: default-scheduler"
