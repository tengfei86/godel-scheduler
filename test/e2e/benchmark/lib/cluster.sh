#!/usr/bin/env bash
# lib/cluster.sh — 集群管理（创建/销毁 kind 集群、KWOK 节点管理）

set -eu

_CLUSTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CLUSTER_LIB_DIR}/utils.sh"

# ── 创建 kind 集群 ──
# 用法: create_kind_cluster [--force-rebuild] [cluster_name] [config]
create_kind_cluster() {
  local force=false
  if [[ "${1:-}" == "--force-rebuild" ]]; then
    force=true; shift
  fi
  local cluster_name="${1:-$KIND_CLUSTER_NAME}"
  local config="${2:-$KIND_CONFIG}"

  log_step "创建 kind 集群: ${cluster_name}"

  if kind get clusters 2>/dev/null | grep -q "^${cluster_name}$"; then
    if [[ "$force" == "true" ]]; then
      log_warn "集群 ${cluster_name} 已存在，强制重建：先销毁"
      destroy_kind_cluster "$cluster_name"
    else
      log_warn "集群 ${cluster_name} 已存在，跳过创建（使用 --force-rebuild 强制重建）"
      return 0
    fi
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

# ── 重启 API Server ──
# 通过删除 kube-apiserver 静态 Pod 触发 kubelet 自动重建，清理连接积压和内存膨胀
restart_apiserver() {
  local container_name="${KIND_CLUSTER_NAME}-control-plane"
  log_info "重启 API Server（清理连接积压）..."

  # 方法: 给 kube-apiserver.yaml 加一个时间戳注解，kubelet 检测到变更自动重启
  local ts
  ts=$(date +%s)
  docker exec "$container_name" bash -c "
    sed -i 's/^    restart-ts:.*/    restart-ts: \"${ts}\"/' /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null
    if ! grep -q 'restart-ts:' /etc/kubernetes/manifests/kube-apiserver.yaml; then
      sed -i '/^  annotations:/a\\    restart-ts: \"${ts}\"' /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null
    fi
    if ! grep -q 'annotations:' /etc/kubernetes/manifests/kube-apiserver.yaml; then
      sed -i '/^metadata:/a\\  annotations:\n    restart-ts: \"${ts}\"' /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null
    fi
  "

  # 等待 API Server 下线再上线
  sleep 5
  local max_wait=60
  for i in $(seq 1 "$max_wait"); do
    if kubectl cluster-info --request-timeout=3s &>/dev/null; then
      log_info "✓ API Server 重启完成 (${i}s)"
      return 0
    fi
    sleep 1
  done
  log_warn "API Server 重启等待超时 (${max_wait}s)，继续执行"
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

# ── 让 kindnet 忽略 KWOK 假节点 ──
patch_kindnet_for_kwok() {
  log_info "Patch kindnet DaemonSet: 排除 KWOK 节点..."

  # 如果已经有 nodeAffinity 排除 fake 节点，跳过
  if kubectl get ds kindnet -n kube-system -o json 2>/dev/null | \
    jq -e '.spec.template.spec.affinity.nodeAffinity' &>/dev/null; then
    log_info "kindnet 已配置 nodeAffinity，跳过"
    return 0
  fi

  kubectl patch ds kindnet -n kube-system --type=merge -p '{
    "spec": {
      "template": {
        "spec": {
          "affinity": {
            "nodeAffinity": {
              "requiredDuringSchedulingIgnoredDuringExecution": {
                "nodeSelectorTerms": [{
                  "matchExpressions": [{
                    "key": "fake.byted.org/node",
                    "operator": "DoesNotExist"
                  }]
                }]
              }
            }
          }
        }
      }
    }
  }'

  log_info "等待 kindnet 滚动更新..."
  kubectl rollout status ds/kindnet -n kube-system --timeout=60s 2>/dev/null || true
  log_info "✓ kindnet 已配置为忽略 KWOK 节点"
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

  # 确保 KWOK 控制器只调度到真实节点，而非 KWOK 假节点
  log_info "Patch kwok-controller: 排除 KWOK 假节点..."
  kubectl patch deployment kwok-controller -n kube-system --type=merge -p '{
    "spec": {
      "template": {
        "spec": {
          "affinity": {
            "nodeAffinity": {
              "requiredDuringSchedulingIgnoredDuringExecution": {
                "nodeSelectorTerms": [{
                  "matchExpressions": [{
                    "key": "fake.byted.org/node",
                    "operator": "DoesNotExist"
                  }]
                }]
              }
            }
          }
        }
      }
    }
  }'

  log_info "等待 kwok-controller 就绪..."
  kubectl rollout status deployment/kwok-controller -n kube-system --timeout=120s 2>/dev/null || true
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
  kubectl get pods -n "${ENO_NAMESPACE}" --no-headers 2>/dev/null || echo "  (未部署)"
  echo ""
  echo "── Prometheus ──"
  kubectl get pods -n "${PROMETHEUS_NAMESPACE}" --no-headers 2>/dev/null || echo "  (未部署)"
  echo ""
}

# ── 验证节点分区分配 ──
show_node_partition() {
  log_info "节点分区分配 (Node Shuffler):"
  local schedulers
  # 支持两种命名方式：scheduler / scheduler-0,1,2
  schedulers=$(kubectl get deployment -n "${ENO_NAMESPACE}" --no-headers 2>/dev/null \
    | awk '{print $1}' | grep -E '^(scheduler|scheduler-)' || true)

  if [[ -z "${schedulers}" ]]; then
    log_warn "未发现 scheduler deployment，跳过节点分区统计"
    return
  fi

  local fake_total
  fake_total=$(kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null | wc -l | tr -d ' ')

  # 检查是否有节点被物理分区（DispatcherNodeShuffle 特性门控）
  local annotated_count
  annotated_count=$(kubectl get nodes -o json 2>/dev/null | \
    jq '[.items[] | select(.metadata.annotations["eno.io/scheduler-name"] != null)] | length')

  if (( annotated_count == 0 )); then
    # 逻辑分区模式：NodeShuffle 未启用，所有 scheduler 共享全部节点
    echo "  模式: 逻辑分区 (DispatcherNodeShuffle 未启用)"
    for sched in $schedulers; do
      echo "  ${sched}: ${fake_total} 个节点 (全部可见)"
    done
    return
  fi

  # 物理分区模式：按注解统计每个 scheduler 拥有的节点
  echo "  模式: 物理分区 (DispatcherNodeShuffle 已启用)"
  local assigned_total=0
  for sched in $schedulers; do
    # 物理分区注解值是 Scheduler CRD 名称（如 eno-scheduler），不是 deployment 名
    # 尝试用 Scheduler CRD 查找对应的调度器名称
    local sched_names
    sched_names=$(kubectl get scheduler --no-headers 2>/dev/null | awk '{print $1}' || true)
    for sname in ${sched_names:-$sched}; do
      local count
      count=$(kubectl get nodes -o json 2>/dev/null | \
        jq "[.items[] | select(.metadata.annotations[\"eno.io/scheduler-name\"]==\"${sname}\")] | length")
      if (( count > 0 )); then
        echo "  ${sname}: ${count} 个节点"
        assigned_total=$((assigned_total + count))
      fi
    done
  done

  local unassigned=$((fake_total - assigned_total))
  if (( unassigned < 0 )); then
    unassigned=0
  fi
  echo "  unassigned: ${unassigned} 个节点"
}
