#!/usr/bin/env bash
# schedulers/teardown.sh — 通用卸载（按组清理调度器 + 残留资源）
#
# 用法:
#   ./teardown.sh [group]
#   group: a|b|c|d|e|all (默认 all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

GROUP="${1:-all}"

log_step "卸载调度器 (group=${GROUP})"

# ── 卸载 Gödel ──
teardown_godel() {
  log_info "卸载 Gödel Scheduler..."
  kubectl delete -k "${MANIFESTS_EMBEDDED}" --ignore-not-found 2>/dev/null || true
  kubectl delete -k "${MANIFESTS_BASE}" --ignore-not-found 2>/dev/null || true
  # 等待 Pod 终止
  kubectl wait --for=delete pod --all -n "${GODEL_NAMESPACE}" --timeout=60s 2>/dev/null || true
  log_info "✓ Gödel 已卸载"
}

# ── 卸载 Volcano ──
teardown_volcano() {
  log_info "卸载 Volcano..."
  helm uninstall volcano -n "${VOLCANO_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${VOLCANO_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  # 清理 CRDs（可选，避免影响后续安装）
  kubectl delete crd -l app.kubernetes.io/managed-by=volcano 2>/dev/null || true
  log_info "✓ Volcano 已卸载"
}

# ── 卸载 Koordinator ──
teardown_koordinator() {
  log_info "卸载 Koordinator..."
  helm uninstall koordinator -n "${KOORDINATOR_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${KOORDINATOR_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  kubectl delete crd -l app.kubernetes.io/managed-by=koordinator 2>/dev/null || true
  log_info "✓ Koordinator 已卸载"
}

# ── 清理 bench namespace ──
teardown_bench() {
  log_info "清理 bench namespace..."
  kubectl delete namespace "${BENCH_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  log_info "✓ bench namespace 已清理"
}

# ── 执行清理 ──
case "$GROUP" in
  a|b)
    teardown_godel
    teardown_bench
    ;;
  c)
    # kube-scheduler 无需卸载（集群自带）
    teardown_godel  # 确保 Gödel 不干扰
    teardown_bench
    ;;
  d)
    teardown_volcano
    teardown_bench
    ;;
  e)
    teardown_koordinator
    teardown_bench
    ;;
  all)
    teardown_godel
    teardown_volcano
    teardown_koordinator
    teardown_bench
    ;;
  *)
    log_error "未知组: ${GROUP} (可选: a|b|c|d|e|all)"
    exit 1
    ;;
esac

sleep 5
log_info "✓ 清理完成"
