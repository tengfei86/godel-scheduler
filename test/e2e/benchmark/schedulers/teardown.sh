#!/usr/bin/env bash
# schedulers/teardown.sh — 通用卸载（按组清理调度器 + 残留资源）
#
# 用法:
#   ./teardown.sh [group]
#   group: a|b|c|d|e|all (默认 all)

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

GROUP="${1:-all}"

log_step "卸载调度器 (group=${GROUP})"

# ── 卸载 ENO ──
teardown_eno() {
  log_info "卸载 ENO Scheduler..."
  kubectl delete -k "${MANIFESTS_EMBEDDED}" --ignore-not-found 2>/dev/null || true
  kubectl delete -k "${MANIFESTS_BASE}" --ignore-not-found 2>/dev/null || true
  # 等待 Pod 终止
  kubectl wait --for=delete pod --all -n "${ENO_NAMESPACE}" --timeout=60s 2>/dev/null || true
  log_info "✓ ENO 已卸载"
}

# ── 卸载原始 Gödel (Group A) ──
teardown_godel() {
  log_info "卸载原始 Gödel Scheduler (godel-system)..."
  kubectl delete -k "${MANIFESTS_GROUP_A}" --ignore-not-found 2>/dev/null || true
  kubectl wait --for=delete pod --all -n "${GODEL_NAMESPACE}" --timeout=60s 2>/dev/null || true
  kubectl delete namespace "${GODEL_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  kubectl delete clusterrolebinding godel --ignore-not-found 2>/dev/null || true
  log_info "✓ Gödel (original) 已卸载"
}

# ── 卸载 Volcano ──
teardown_volcano() {
  log_info "卸载 Volcano..."
  helm uninstall volcano -n "${VOLCANO_NAMESPACE}" --wait --timeout 120s 2>/dev/null || true

  # 先删 webhook，避免已下线的 webhook endpoint 拦截 API 请求
  log_info "  清理 Volcano webhook 配置..."
  kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep -i 'volcano' | xargs -r kubectl delete 2>/dev/null || true
  kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep -i 'volcano' | xargs -r kubectl delete 2>/dev/null || true

  kubectl delete namespace "${VOLCANO_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  # CRDs
  for crd in $(kubectl get crd -o name 2>/dev/null | grep -i 'volcano'); do
    kubectl patch "$crd" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl delete "$crd" --ignore-not-found --timeout=30s 2>/dev/null || true
  done
  log_info "✓ Volcano 已卸载"
}

# ── 卸载 Koordinator ──
teardown_koordinator() {
  log_info "卸载 Koordinator..."
  helm uninstall koordinator -n "${KOORDINATOR_NAMESPACE}" --wait --timeout 120s 2>/dev/null || true

  # 先删 webhook，避免已下线的 webhook endpoint 拦截后续 API 请求导致 context deadline exceeded
  log_info "  清理 Koordinator webhook 配置..."
  kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/name=koordinator --ignore-not-found 2>/dev/null || true
  kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/name=koordinator --ignore-not-found 2>/dev/null || true
  # 兜底：按名称前缀删除（部分版本不带 label）
  kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep -i 'koordinator\|koord' | xargs -r kubectl delete 2>/dev/null || true
  kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep -i 'koordinator\|koord' | xargs -r kubectl delete 2>/dev/null || true

  # 清理 CRDs（移除 finalizer 防止卡住）
  log_info "  清理 Koordinator CRDs..."
  for crd in $(kubectl get crd -o name 2>/dev/null | grep -i 'koordinator\|slo.koordinator'); do
    kubectl patch "$crd" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl delete "$crd" --ignore-not-found --timeout=30s 2>/dev/null || true
  done

  # 删除 namespace
  kubectl delete namespace "${KOORDINATOR_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  # 如果 namespace 卡在 Terminating，强制清理 finalizer
  if kubectl get namespace "${KOORDINATOR_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
    log_warn "  namespace ${KOORDINATOR_NAMESPACE} 卡在 Terminating，清理 finalizer..."
    kubectl get namespace "${KOORDINATOR_NAMESPACE}" -o json 2>/dev/null \
      | python3 -c "import sys,json; ns=json.load(sys.stdin); ns['spec']['finalizers']=[]; json.dump(ns,sys.stdout)" \
      | kubectl replace --raw "/api/v1/namespaces/${KOORDINATOR_NAMESPACE}/finalize" -f - 2>/dev/null || true
  fi

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
  a)
    teardown_godel
    teardown_eno  # 确保 eno 不残留
    teardown_bench
    ;;
  b)
    teardown_eno
    teardown_godel  # 确保 godel 不残留
    teardown_bench
    ;;
  c)
    # kube-scheduler 无需卸载（集群自带）
    teardown_eno
    teardown_godel
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
    teardown_eno
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
