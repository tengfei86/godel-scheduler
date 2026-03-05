#!/bin/bash
# lib/utils.sh — 通用函数（日志、等待、颜色输出）

set -euo pipefail

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── 日志函数 ──
log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $(date '+%H:%M:%S') $*"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${PURPLE}[DEBUG]${NC} $(date '+%H:%M:%S') $*" || true; }

# ── 分隔线 ──
separator() {
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  $*"
  echo "════════════════════════════════════════════════════════════"
  echo ""
}

# ── 等待 Pod 就绪 ──
# 用法: wait_pods_ready <namespace> <label-selector> <expected-count> <timeout-seconds>
wait_pods_ready() {
  local ns="${1}"
  local selector="${2}"
  local expected="${3}"
  local timeout="${4:-300}"
  local elapsed=0

  log_info "等待 ${expected} 个 Pod 就绪 (ns=${ns}, selector=${selector}, timeout=${timeout}s)..."

  while (( elapsed < timeout )); do
    local ready
    ready=$(kubectl get pods -n "$ns" -l "$selector" --no-headers 2>/dev/null \
      | grep -c "Running" || true)
    if (( ready >= expected )); then
      log_info "✓ ${ready}/${expected} Pod 就绪"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    log_debug "  ${ready}/${expected} 就绪... (${elapsed}s)"
  done

  log_error "超时：仅 ${ready:-0}/${expected} Pod 就绪"
  return 1
}

# ── 等待 Deployment 就绪 ──
# 用法: wait_deployment_ready <namespace> <deployment-name> <timeout-seconds>
wait_deployment_ready() {
  local ns="${1}"
  local deploy="${2}"
  local timeout="${3:-300}"

  log_info "等待 Deployment ${deploy} 就绪 (ns=${ns}, timeout=${timeout}s)..."
  if kubectl rollout status deployment/"$deploy" -n "$ns" --timeout="${timeout}s" 2>/dev/null; then
    log_info "✓ Deployment ${deploy} 就绪"
    return 0
  else
    log_error "✗ Deployment ${deploy} 未就绪"
    return 1
  fi
}

# ── 等待所有 Bench Pod 调度完成 ──
# 用法: wait_all_scheduled <namespace> <timeout-seconds>
wait_all_scheduled() {
  local ns="${1:-bench}"
  local timeout="${2:-3600}"
  local elapsed=0

  log_info "等待 namespace=${ns} 中所有 Pod 调度完成 (timeout=${timeout}s)..."

  while (( elapsed < timeout )); do
    local pending
    pending=$(kubectl get pods -n "$ns" --field-selector=status.phase=Pending \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if (( pending == 0 )); then
      local total
      total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      log_info "✓ 所有 ${total} 个 Pod 已调度完成"
      return 0
    fi
    sleep "${POLL_INTERVAL:-5}"
    elapsed=$((elapsed + ${POLL_INTERVAL:-5}))
    if (( elapsed % 30 == 0 )); then
      log_info "  仍有 ${pending} 个 Pending Pod... (${elapsed}s)"
    fi
  done

  log_error "超时：仍有 Pending Pod"
  return 1
}

# ── 清理 bench namespace ──
cleanup_bench() {
  local ns="${1:-bench}"
  log_step "清理 namespace=${ns}..."
  kubectl delete namespace "$ns" --ignore-not-found --wait=true 2>/dev/null || true
  sleep 10
  log_info "✓ namespace=${ns} 已清理"
}

# ── 计算持续时间（人类可读） ──
format_duration() {
  local seconds=$1
  local hours=$((seconds / 3600))
  local minutes=$(( (seconds % 3600) / 60 ))
  local secs=$((seconds % 60))
  if (( hours > 0 )); then
    printf "%dh%dm%ds" "$hours" "$minutes" "$secs"
  elif (( minutes > 0 )); then
    printf "%dm%ds" "$minutes" "$secs"
  else
    printf "%ds" "$secs"
  fi
}

# ── 检查命令是否存在 ──
require_cmd() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "必需的命令 '${cmd}' 未找到，请先安装"
      return 1
    fi
  done
}

# ── 确认操作（交互式） ──
confirm() {
  local msg="${1:-确认继续？}"
  if [[ "${AUTO_CONFIRM:-0}" == "1" ]]; then
    return 0
  fi
  read -rp "$(echo -e "${YELLOW}${msg} [y/N]${NC} ")" answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ── 获取当前时间戳 ──
now_ts() {
  date +%s
}

# ── 获取 ISO 时间 ──
now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}
