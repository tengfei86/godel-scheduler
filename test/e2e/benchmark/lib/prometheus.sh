#!/usr/bin/env bash
# lib/prometheus.sh — Prometheus 操作（部署、等待就绪、数据导出）

set -eu

_PROM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_PROM_LIB_DIR}/utils.sh"

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
    if curl -s "${PROMETHEUS_ADDR}/-/ready" 2>/dev/null | grep -qi "ready"; then
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
# 自动处理:
#   1. 时间跨度过长时放大 step，避免数据点过多导致 Prometheus 超时
#   2. 设置 curl --max-time 防止无限等待
#   3. 失败后逐步放大 step 重试（2x → 4x → 8x），直到成功或达到最大重试
#   4. 使用临时文件，避免损坏已有输出；最终失败写入空数据 JSON
prometheus_query_range() {
  local query="${1}"
  local start="${2}"
  local end="${3}"
  local output="${4}"
  local step="${5:-$PROMETHEUS_STEP}"

  # 自动调整 step：如果数据点数超过 MAX_POINTS，放大 step
  local step_seconds
  step_seconds=$(echo "$step" | sed 's/s$//')
  local duration=$(( end - start ))
  local max_points="${PROMETHEUS_MAX_POINTS:-11000}"
  local estimated_points=$(( duration / step_seconds ))
  if (( estimated_points > max_points )); then
    step_seconds=$(( (duration + max_points - 1) / max_points ))
    step="${step_seconds}s"
    log_debug "  step 自动放大为 ${step} (${estimated_points} 点 → ~${max_points} 点)"
  fi

  local encoded_query
  encoded_query=$(printf '%s' "$query" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null \
    || echo "$query")

  local timeout="${PROMETHEUS_QUERY_TIMEOUT:-300}"
  local max_retries=4
  local attempt=0
  local cur_step=$step_seconds

  while (( attempt < max_retries )); do
    attempt=$((attempt + 1))
    local url="${PROMETHEUS_ADDR}/api/v1/query_range?query=${encoded_query}&start=${start}&end=${end}&step=${cur_step}s&timeout=${timeout}s"

    # 写入临时文件，避免损坏已有输出
    local tmpfile="${output}.tmp"
    curl -s --max-time "$timeout" --retry 2 --retry-delay 5 \
      "$url" > "$tmpfile" 2>/dev/null || true

    # 验证: 必须是合法 JSON 且 status == success
    if jq -e '.status == "success"' "$tmpfile" &>/dev/null; then
      mv -f "$tmpfile" "$output"
      if (( attempt > 1 )); then
        log_debug "✓ 重试成功: $(basename "$output") (step=${cur_step}s, 第${attempt}次)"
      else
        log_debug "✓ 查询成功: $(basename "$output")"
      fi
      return 0
    fi

    # 查看失败原因
    local err_type="unknown"
    if [[ ! -s "$tmpfile" ]]; then
      err_type="empty/timeout"
    elif ! python3 -c "import json,sys; json.load(sys.stdin)" < "$tmpfile" 2>/dev/null; then
      err_type="truncated_json"
    else
      err_type=$(jq -r '.errorType // .error // "query_error"' "$tmpfile" 2>/dev/null || echo "parse_error")
    fi
    rm -f "$tmpfile"

    if (( attempt < max_retries )); then
      cur_step=$(( cur_step * 2 ))
      log_warn "查询失败(${err_type})，重试 step=${cur_step}s (${attempt}/${max_retries}): $(basename "$output")"
    else
      log_warn "✗ 查询最终失败(${err_type}): $(basename "$output") (${max_retries}次重试均失败)"
      # 写入空的成功响应，避免后续解析报错
      echo '{"status":"success","data":{"resultType":"matrix","result":[]}}' > "$output"
    fi
  done
}

# ── 执行即时查询 ──
# 用法: prometheus_query_instant <query> [time]
prometheus_query_instant() {
  local query="${1}"
  local time="${2:-}"

  local url="${PROMETHEUS_ADDR}/api/v1/query?query=$(printf '%s' "$query" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")"
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
