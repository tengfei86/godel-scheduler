#!/usr/bin/env bash
# setup-cluster.sh — Phase 0: 一键搭建集群 + KWOK 节点 + Prometheus
#
# 用法:
#   ./setup-cluster.sh [--force-rebuild] [--rebuild-image] [scale]
#   scale: s1|s2|s3|s4|s5 (默认 s2=1000节点)
#
# 选项:
#   --force-rebuild    销毁已有集群并重新创建
#   --rebuild-image     重新编译 Gödel 并构建 Docker 镜像
#
# 示例:
#   ./setup-cluster.sh s3                       # 创建 5000 个 KWOK 节点
#   ./setup-cluster.sh --force-rebuild           # 强制重建集群
#   ./setup-cluster.sh --rebuild-image s2        # 重建镜像 + 1000 节点

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

# ── 参数解析 ──
FORCE_FLAG=""
REBUILD_IMAGE=false
SCALE="s2"
while [[ $# -gt 0 ]]; do
  case $1 in
    --force-rebuild)  FORCE_FLAG="--force-rebuild"; shift ;;
    --rebuild-image)  REBUILD_IMAGE=true; shift ;;
    s[1-5])           SCALE="$1"; shift ;;
    *)                echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

# ── 验证依赖 ──
require_cmd kubectl kind docker jq curl

separator "Phase 0: 环境准备"

NODE_COUNT="${SCALE_NODES[$SCALE]:-1000}"
log_info "目标规模: ${SCALE} (${NODE_COUNT} 节点)"

# ── Step 1: 创建 kind 集群 ──
log_step "Step 1/8: 创建 kind 集群"
create_kind_cluster $FORCE_FLAG

# ── Step 2: Patch kindnet 以忽略 KWOK 假节点 ──
log_step "Step 2/8: Patch kindnet"
patch_kindnet_for_kwok

# ── Step 3: 部署 KWOK ──
log_step "Step 3/8: 部署 KWOK 控制器"
deploy_kwok

# ── Step 4: 创建模拟节点 ──
log_step "Step 4/8: 创建 ${NODE_COUNT} 个 KWOK 模拟节点"
create_kwok_nodes "$NODE_COUNT"

# ── Step 5: 部署事件专用 etcd ──
log_step "Step 5/8: 部署事件专用 etcd (分离 events 写入)"
bash "${SCRIPT_DIR}/cluster/deploy-etcd-events.sh" "${KIND_CLUSTER_NAME}"

# ── Step 6: 构建 Gödel 镜像并加载到 kind ──
log_step "Step 6/8: 构建 Gödel 镜像"
if [[ "$REBUILD_IMAGE" == true ]] || ! docker image inspect "${ENO_IMAGE}" &>/dev/null; then
  log_info "编译 Gödel (linux/amd64)..."
  (cd "${PROJECT_ROOT}" && GO_BUILD_PLATFORMS=linux/amd64 make build)
  log_info "构建 Docker 镜像 ${ENO_IMAGE}..."
  docker build --no-cache -f "${PROJECT_ROOT}/docker/eno-local.Dockerfile" -t "${ENO_IMAGE}" "${PROJECT_ROOT}"
  log_info "✓ 镜像构建完成"
else
  log_info "镜像 ${ENO_IMAGE} 已存在，跳过构建（使用 --rebuild-image 强制重建）"
fi
ensure_image_loaded "${ENO_IMAGE}"

# ── Step 7: 提示 Prometheus 安装方式 ──
log_step "Step 7/8: Prometheus 说明"
log_info "Prometheus 将在部署调度器时通过 kustomize overlay 自动安装"
log_info "  kubectl apply -k manifests/monitoring/overlays/group-{a,b,c,d,e}/"
log_info "  每个 overlay 包含该组对应的 scrape targets + recording rules"
log_info ""
log_info "如需提前手动安装（使用 base 配置）："
log_info "  kubectl apply -k ${MANIFESTS_MONITORING_BASE}"

# ── Step 8: 验证 ──
log_step "Step 8/8: 验证环境"
show_cluster_status

separator "环境准备完成"
log_info "集群: ${KIND_CLUSTER_NAME}"
log_info "节点数: ${NODE_COUNT}"
log_info "Prometheus: ${PROMETHEUS_ADDR}"
log_info ""
log_info "下一步: 部署调度器"
log_info "  组 A: bash schedulers/deploy-group-a.sh"
log_info "  组 B: bash schedulers/deploy-group-b.sh"
