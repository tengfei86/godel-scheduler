#!/bin/bash
# setup-cluster.sh — Phase 0: 一键搭建集群 + KWOK 节点 + Prometheus
#
# 用法:
#   ./setup-cluster.sh [scale]
#   scale: s1|s2|s3|s4|s5 (默认 s2=1000节点)
#
# 示例:
#   ./setup-cluster.sh s3    # 创建 5000 个 KWOK 节点

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

SCALE="${1:-s2}"

# ── 验证依赖 ──
require_cmd kubectl kind docker jq curl

separator "Phase 0: 环境准备"

NODE_COUNT="${SCALE_NODES[$SCALE]:-1000}"
log_info "目标规模: ${SCALE} (${NODE_COUNT} 节点)"

# ── Step 1: 创建 kind 集群 ──
log_step "Step 1/5: 创建 kind 集群"
create_kind_cluster

# ── Step 2: 部署 KWOK ──
log_step "Step 2/5: 部署 KWOK 控制器"
deploy_kwok

# ── Step 3: 创建模拟节点 ──
log_step "Step 3/5: 创建 ${NODE_COUNT} 个 KWOK 模拟节点"
create_kwok_nodes "$NODE_COUNT"

# ── Step 4: 部署 Prometheus ──
log_step "Step 4/5: 部署 Prometheus"
deploy_prometheus

# ── Step 5: 验证 ──
log_step "Step 5/5: 验证环境"
wait_prometheus_ready 60
show_cluster_status

separator "环境准备完成"
log_info "集群: ${KIND_CLUSTER_NAME}"
log_info "节点数: ${NODE_COUNT}"
log_info "Prometheus: ${PROMETHEUS_ADDR}"
log_info ""
log_info "下一步: 部署调度器"
log_info "  组 A: bash schedulers/deploy-group-a.sh"
log_info "  组 B: bash schedulers/deploy-group-b.sh"
