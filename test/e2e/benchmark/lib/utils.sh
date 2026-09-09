#!/usr/bin/env bash
# lib/utils.sh — 通用函数（日志、等待、颜色输出）

set -eu

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

# ── API Server 连通性检查 ──
check_api_server() {
  local timeout="${1:-10}"
  log_info "检查 API Server 连通性 (timeout=${timeout}s)..."
  if ! kubectl cluster-info --request-timeout="${timeout}s" &>/dev/null; then
    log_error "无法连接 API Server，请确认集群可用"
    log_error "  检查: kubectl cluster-info"
    return 1
  fi
  log_info "✓ API Server 可用"
}

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
# 用法: wait_all_scheduled <namespace> <timeout-seconds> [expected-total]
# 严格模式 (提供 expected-total):
#   同时要求 pending==0 且 total==expected；否则视为失败（submissions 缺失或 pod 丢失）。
# 宽松模式 (未提供 expected-total): 仅要求 pending==0（旧行为，保留兼容）。
# 返回:
#   0 成功
#   1 超时（仍有 Pending）
#   2 数量不匹配（无 Pending 但 total ≠ expected；submissions 不完整）
wait_all_scheduled() {
  local ns="${1:-bench}"
  local timeout="${2:-3600}"
  local expected="${3:-}"
  local elapsed=0

  if [[ -n "$expected" ]]; then
    log_info "等待 namespace=${ns} 中 ${expected} 个 Pod 全部调度完成 (严格 100%, timeout=${timeout}s)..."
  else
    log_info "等待 namespace=${ns} 中所有 Pod 调度完成 (timeout=${timeout}s)..."
  fi

  while (( elapsed < timeout )); do
    local pending total scheduled
    pending=$(kubectl get pods -n "$ns" --field-selector=status.phase=Pending \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    scheduled=$((total - pending))

    if (( pending == 0 )); then
      if [[ -z "$expected" ]]; then
        log_info "✓ 所有 ${total} 个 Pod 已调度完成"
        return 0
      fi
      if (( total == expected )); then
        log_info "✓ ${expected} 个 Pod 全部调度完成 (scheduled=${scheduled}, total=${total})"
        return 0
      fi
      log_error "调度数不达标: expected=${expected}, total in ns=${total}, scheduled=${scheduled}"
      log_error "  可能原因: podgen 提交失败（webhook/quota/RBAC）或 Pod 提前被清理"
      return 2
    fi

    sleep "${POLL_INTERVAL:-5}"
    elapsed=$((elapsed + ${POLL_INTERVAL:-5}))
    if (( elapsed % 30 == 0 )); then
      if [[ -n "$expected" ]]; then
        log_info "  scheduled=${scheduled}/${expected}, pending=${pending}, total_in_ns=${total} ... (${elapsed}s)"
      else
        log_info "  仍有 ${pending} 个 Pending Pod... (${elapsed}s)"
      fi
    fi
  done

  log_error "超时：仍有 Pending Pod（scheduled=${scheduled:-?}/${expected:-?}, pending=${pending:-?}）"
  return 1
}

# ── 等待 API Server + Admission webhook 完全就绪 ──
# 部署脚本的 kubectl rollout status 只保证 Deployment 副本 Ready，
# 但对应的 admission webhook Service Endpoints 可能还没被 apiserver 观测到，
# 导致 podgen 起来后前几十个 pod 全部报 "failed calling webhook" 之类错误、
# 等 endpoints 热了才恢复。
# 这里用 --dry-run=server 走一次完整 admission 链，通过一次即视为就绪。
# 用法: wait_ready_to_create_pods <namespace> <scheduler_name> [timeout]
wait_ready_to_create_pods() {
  local ns="${1:-bench}"
  local sched="${2:-default-scheduler}"
  local timeout="${3:-120}"
  local elapsed=0
  local err=""

  log_info "验证 admission 链就绪 (ns=${ns}, scheduler=${sched}, timeout=${timeout}s)..."

  # 确保 ns 存在（--dry-run=server 需要）
  kubectl create ns "$ns" >/dev/null 2>&1 || true

  while (( elapsed < timeout )); do
    if err=$(kubectl apply --dry-run=server -f - <<YAML 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: podgen-smoke-$$
  namespace: ${ns}
spec:
  schedulerName: ${sched}
  containers:
  - {name: c, image: registry.k8s.io/pause:3.9}
YAML
); then
      log_info "✓ admission 链已就绪 (耗时 ${elapsed}s)"
      return 0
    fi
    if (( elapsed > 0 && elapsed % 10 == 0 )); then
      log_warn "  ${elapsed}s: 尚未就绪, 最近错误: $(echo "$err" | head -n1 | cut -c1-160)"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  log_error "超时: admission 链仍未就绪 (最后错误: $(echo "$err" | head -n1))"
  return 1
}

# ── 清理 bench namespace ──
# 大规模场景 (s3/s4, 5w-10w pods) 下 kubectl delete --wait=true 会因超时提前返回，
# 此时 namespace 仍在 Terminating，紧接着的 pods.Create() 会全部拿到:
#   "namespaces ... is forbidden: unable to create new content in namespace ...
#    because it is being terminated"
# 所以这里发起 delete 后主动轮询，直到 API Server 里彻底看不到该 namespace 才返回。
cleanup_bench() {
  local ns="${1:-bench}"
  local timeout="${CLEANUP_BENCH_TIMEOUT:-900}"   # 秒；s5 场景可再放宽
  log_step "清理 namespace=${ns} (最多等 ${timeout}s)..."

  kubectl delete namespace "$ns" --ignore-not-found --wait=false 2>/dev/null || true

  local elapsed=0
  while kubectl get namespace "$ns" &>/dev/null; do
    if (( elapsed >= timeout )); then
      log_warn "namespace ${ns} 清理超时 (${timeout}s)，仍处 Terminating，强制继续"
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  log_info "✓ namespace=${ns} 已清理 (耗时 ${elapsed}s)"
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
