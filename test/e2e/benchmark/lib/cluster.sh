#!/usr/bin/env bash
# lib/cluster.sh — 集群管理（创建/销毁 kind 集群、KWOK 节点管理）

set -eu

_CLUSTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CLUSTER_LIB_DIR}/utils.sh"

# ── 创建 kind 集群 ──
create_kind_cluster() {
  local cluster_name="${1:-$KIND_CLUSTER_NAME}"
  local config="${2:-$KIND_CONFIG}"

  log_step "创建 kind 集群: ${cluster_name}"

  if kind get clusters 2>/dev/null | grep -q "^${cluster_name}$"; then
    log_warn "集群 ${cluster_name} 已存在，跳过创建"
    return 0
  fi

  kind create cluster \
    --name "$cluster_name" \
    --config "$config" \
    --wait 5m

  log_info "✓ kind 集群 ${cluster_name} 创建成功"

  # 调整 API Server 参数
  tune_apiserver
}

# ── 销毁 kind 集群 ──
destroy_kind_cluster() {
  local cluster_name="${1:-$KIND_CLUSTER_NAME}"

  log_step "销毁 kind 集群: ${cluster_name}"
  kind delete cluster --name "$cluster_name" 2>/dev/null || true
  log_info "✓ kind 集群 ${cluster_name} 已销毁"
}

# ── 调整 API Server 参数 ──
tune_apiserver() {
  log_info "调整 API Server inflight 参数..."
  local container_name="${KIND_CLUSTER_NAME}-control-plane"

  # 检查当前是否已有合适参数
  docker exec "$container_name" cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | \
    grep -q "max-mutating-requests-inflight=${APISERVER_MAX_MUTATING_INFLIGHT}" && {
    log_info "API Server 参数已配置，跳过"
    return 0
  }

  # 通过 sed 追加参数（如果尚未存在）
  docker exec "$container_name" bash -c "
    sed -i '/--etcd-servers/a\\    - --max-mutating-requests-inflight=${APISERVER_MAX_MUTATING_INFLIGHT}' \
      /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || true
    sed -i '/--etcd-servers/a\\    - --max-requests-inflight=${APISERVER_MAX_REQUESTS_INFLIGHT}' \
      /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || true
  "

  log_info "等待 API Server 重启..."
  sleep 30
  kubectl wait --for=condition=Ready node --all --timeout=120s 2>/dev/null || true
  log_info "✓ API Server 参数已调整"
}

# ── 确保镜像已加载到 kind 集群 ──
# 用法: ensure_image_loaded <image>
ensure_image_loaded() {
  local image="${1:?ensure_image_loaded <image>}"
  local cluster_name="${2:-$KIND_CLUSTER_NAME}"
  local node="${cluster_name}-control-plane"

  # 检查 kind node 里是否已有该镜像
  if docker exec "$node" crictl images -q 2>/dev/null | grep -q "$(docker inspect --format='{{.Id}}' "$image" 2>/dev/null)"; then
    log_info "镜像 ${image} 已在 kind 集群中"
    return 0
  fi

  log_info "加载镜像 ${image} 到 kind 集群 ${cluster_name}..."
  kind load docker-image "$image" --name "$cluster_name"
  log_info "✓ 镜像 ${image} 加载完成"
}

# ── 部署 KWOK 控制器 ──
deploy_kwok() {
  log_step "部署 KWOK 控制器"

  if kubectl get deployment kwok-controller -n kube-system &>/dev/null; then
    log_warn "KWOK 控制器已部署，跳过"
    return 0
  fi

  if [[ -f "$KWOK_DEPLOY_SCRIPT" ]]; then
    bash "$KWOK_DEPLOY_SCRIPT"
  else
    log_error "KWOK 部署脚本不存在: ${KWOK_DEPLOY_SCRIPT}"
    return 1
  fi

  log_info "✓ KWOK 控制器部署完成"
}

# ── 创建 KWOK 模拟节点 ──
# 用法: create_kwok_nodes <count>
# 精确调整节点数到 count：多了先清理再创建，少了补足，相等则跳过。
create_kwok_nodes() {
  local count="${1:?用法: create_kwok_nodes <count>}"

  log_step "调整 KWOK 模拟节点到 ${count} 个 (并行度=${NODE_CREATE_PARALLELISM})"

  # 先检查当前已有节点数
  local existing
  existing=$(kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null | wc -l | tr -d ' ')
  log_info "当前已有 ${existing} 个 KWOK 节点，目标 ${count} 个"

  if (( existing == count )); then
    log_info "✓ 节点数已匹配，跳过"
    return 0
  fi

  if (( existing > count )); then
    log_warn "节点过多 (${existing} > ${count})，先清理全部再重建..."
    cleanup_kwok_nodes
    sleep 10
    existing=0
  fi

  local to_create=$((count - existing))
  log_info "需要创建 ${to_create} 个节点..."

  seq "$to_create" | xargs -I {} -P "$NODE_CREATE_PARALLELISM" \
    bash -c "kubectl create -f ${NODE_TEMPLATE} 2>/dev/null" || true

  # 等待节点就绪
  log_info "等待所有节点 Ready..."
  local elapsed=0
  while (( elapsed < WAIT_READY_TIMEOUT )); do
    local ready
    ready=$(kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null \
      | grep -c " Ready" || true)
    if (( ready >= count )); then
      log_info "✓ ${ready}/${count} 个 KWOK 节点已 Ready"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  local final_ready
  final_ready=$(kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null \
    | grep -c " Ready" || true)
  log_warn "超时，当前 ${final_ready}/${count} 个节点 Ready"
}

# ── 清理 KWOK 模拟节点 ──
cleanup_kwok_nodes() {
  log_step "清理所有 KWOK 模拟节点..."
  kubectl delete node -l fake.byted.org/node --wait=false 2>/dev/null || true
  sleep 5
  log_info "✓ KWOK 节点已清理"
}

# ── 显示集群状态 ──
show_cluster_status() {
  separator "集群状态"
  echo "── 节点 ──"
  kubectl get nodes --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  总节点数: {}"
  kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  KWOK 节点数: {}"
  echo ""
  echo "── Gödel 组件 ──"
  kubectl get pods -n "${GODEL_NAMESPACE}" --no-headers 2>/dev/null || echo "  (未部署)"
  echo ""
  echo "── Prometheus ──"
  kubectl get pods -n "${PROMETHEUS_NAMESPACE}" --no-headers 2>/dev/null || echo "  (未部署)"
  echo ""
}

# ── 验证节点分区分配 ──
show_node_partition() {
  log_info "节点分区分配 (Node Shuffler):"
  local schedulers
  schedulers=$(kubectl get deployment -n "${GODEL_NAMESPACE}" --no-headers 2>/dev/null \
    | awk '{print $1}' | grep "^scheduler-" || echo "scheduler-0 scheduler-1 scheduler-2")

  for sched in $schedulers; do
    local count
    count=$(kubectl get nodes -o json 2>/dev/null | \
      jq "[.items[] | select(.metadata.annotations[\"godel.bytedance.com/scheduler-name\"]==\"${sched}\")] | length")
    echo "  ${sched}: ${count} 个节点"
  done
}
