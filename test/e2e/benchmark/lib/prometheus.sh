#!/bin/bash
# lib/prometheus.sh — Prometheus 操作（部署、等待就绪、数据导出）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ── 部署 Prometheus ──
deploy_prometheus() {
  log_step "部署 Prometheus"

  if kubectl get deployment prometheus -n "${PROMETHEUS_NAMESPACE}" &>/dev/null; then
    log_warn "Prometheus 已部署"
    return 0
  fi

  kubectl apply -k "${MANIFESTS_MONITORING_BASE}"
  wait_deployment_ready "${PROMETHEUS_NAMESPACE}" "prometheus" 120
  log_info "✓ Prometheus 部署完成 (NodePort 30090)"
}

# ── 等待 Prometheus 可达 ──
wait_prometheus_ready() {
  local timeout="${1:-120}"
  local elapsed=0

  log_info "等待 Prometheus 可达 (${PROMETHEUS_ADDR})..."

  while (( elapsed < timeout )); do
    if curl -s "${PROMETHEUS_ADDR}/-/ready" 2>/dev/null | grep -q "ready"; then
      log_info "✓ Prometheus 就绪"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  log_error "Prometheus 不可达 (超时=${timeout}s)"
  return 1
}

# ── 验证 Prometheus 可以抓取调度器指标 ──
verify_prometheus_targets() {
  log_info "检查 Prometheus scrape targets..."
  local targets
  targets=$(curl -s "${PROMETHEUS_ADDR}/api/v1/targets" 2>/dev/null | \
    jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"' 2>/dev/null || echo "(无法获取)")
  echo "$targets"
}

# ── 从 Prometheus 导出查询结果 ──
# 用法: prometheus_query_range <query> <start_ts> <end_ts> <output_file> [step]
prometheus_query_range() {
  local query="${1}"
  local start="${2}"
  local end="${3}"
  local output="${4}"
  local step="${5:-$PROMETHEUS_STEP}"

  local encoded_query
  encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${query}'))" 2>/dev/null \
    || echo "$query")

  curl -s --retry 3 --retry-delay 2 \
    "${PROMETHEUS_ADDR}/api/v1/query_range?query=${encoded_query}&start=${start}&end=${end}&step=${step}" \
    > "$output"

  if jq -e '.status == "success"' "$output" &>/dev/null; then
    log_debug "✓ 查询成功: $(basename "$output")"
  else
    log_warn "查询可能失败: $(basename "$output")"
  fi
}

# ── 执行即时查询 ──
# 用法: prometheus_query_instant <query> [time]
prometheus_query_instant() {
  local query="${1}"
  local time="${2:-}"

  local url="${PROMETHEUS_ADDR}/api/v1/query?query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${query}'))")"
  [[ -n "$time" ]] && url="${url}&time=${time}"

  curl -s --retry 3 --retry-delay 2 "$url"
}

# ── 重启 Prometheus（重置指标） ──
restart_prometheus() {
  log_info "重启 Prometheus..."
  kubectl rollout restart deployment/prometheus -n "${PROMETHEUS_NAMESPACE}" 2>/dev/null || true
  sleep 10
  wait_prometheus_ready 120
}
