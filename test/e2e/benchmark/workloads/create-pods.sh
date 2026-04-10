#!/usr/bin/env bash
# workloads/create-pods.sh — 按固定速率批量创建 Pod
#
# 底层使用 Go 编写的 podgen v2 工具 (client-go 直连 API Server)
# v1 使用 kubectl apply fork/exec，在 1000 pods/s 时只能达到 ~200 pods/s
# v2 使用 client-go + HTTP/2 多路复用，可稳定达到 2000+ pods/s
#
# 用法:
#   ./create-pods.sh <rate> <total> <scheduler_name> [cpu] [mem] [workload_type]
#
# 参数:
#   rate            - 每秒创建的 Pod 数量
#   total           - 总 Pod 数量
#   scheduler_name  - schedulerName (eno-scheduler|default-scheduler|volcano|koord-scheduler)
#   cpu             - CPU 请求 (millicores, 默认 100)
#   mem             - 内存请求 (Mi, 默认 128)
#   workload_type   - basic|burst|gang|heterogeneous (默认 basic)
#
# 环境变量 (可选):
#   PODGEN_WORKERS  - 并发 goroutine 数 (默认 64)
#   PODGEN_QPS      - client-go QPS 限速 (默认 3000)
#   PODGEN_BURST    - client-go burst 限速 (默认 6000)
#   PODGEN_DRY_RUN  - 设为 1 则仅计数不实际创建
#
# 示例:
#   ./create-pods.sh 500 50000 eno-scheduler 100 128
#   ./create-pods.sh 1000 100000 eno-scheduler 100 128 basic
#   PODGEN_WORKERS=128 ./create-pods.sh 2000 200000 eno-scheduler

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${BENCHMARK_DIR}/config.sh"
source "${BENCHMARK_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/workload-matrix.sh"

# ── 参数解析 ──
RATE="${1:?用法: create-pods.sh <rate> <total> <scheduler_name> [cpu] [mem] [workload_type]}"
TOTAL="${2:?缺少参数: total}"
SCHED_NAME="${3:?缺少参数: scheduler_name}"
CPU="${4:-100}"
MEM="${5:-128}"
WTYPE="${6:-basic}"

NAMESPACE="${BENCH_NAMESPACE}"
PODGEN_DIR="${SCRIPT_DIR}/podgen"
PODGEN_BIN="${PODGEN_DIR}/podgen"

# ── 可调参数 ──
WORKER_COUNT="${PODGEN_WORKERS:-64}"
QPS="${PODGEN_QPS:-3000}"
BURST="${PODGEN_BURST:-6000}"
DRY_RUN="${PODGEN_DRY_RUN:-0}"

# ── 自动调参 ──
auto_tune_params() {
  local r=$1

  # workers: 高速率需要更多并发 goroutine
  if [[ "$WORKER_COUNT" == "64" ]]; then
    if (( r >= 2000 )); then
      WORKER_COUNT=200
    elif (( r >= 1000 )); then
      WORKER_COUNT=128
    elif (( r >= 500 )); then
      WORKER_COUNT=96
    fi
  fi

  # QPS/Burst: 确保 client-go 限速不成为瓶颈 (≥2x target rate)
  if [[ "$QPS" == "3000" ]]; then
    local min_qps=$(( r * 2 ))
    (( min_qps > QPS )) && QPS=$min_qps
    BURST=$(( QPS * 2 ))
  fi

  log_info "  调参: workers=${WORKER_COUNT}, qps=${QPS}, burst=${BURST}"
}

# ── 编译 podgen ──
build_podgen() {
  if [[ -x "$PODGEN_BIN" ]]; then
    local src_mtime bin_mtime
    src_mtime=$(stat -c %Y "${PODGEN_DIR}/main.go" 2>/dev/null || stat -f %m "${PODGEN_DIR}/main.go" 2>/dev/null || echo 0)
    bin_mtime=$(stat -c %Y "$PODGEN_BIN" 2>/dev/null || stat -f %m "$PODGEN_BIN" 2>/dev/null || echo 0)
    if (( bin_mtime >= src_mtime )); then
      log_info "  podgen 已是最新，跳过编译"
      return 0
    fi
  fi

  log_info "  编译 podgen v2 (client-go)..."
  if ! command -v go &>/dev/null; then
    log_error "未找到 go 编译器，请安装 Go 1.21+"
    log_error "  或手动编译: cd ${PODGEN_DIR} && CGO_ENABLED=0 go build -ldflags '-s -w' -o podgen ."
    exit 1
  fi

  (cd "$PODGEN_DIR" && CGO_ENABLED=0 go build -ldflags '-s -w' -o podgen .) || {
    log_error "podgen 编译失败"
    exit 1
  }
  log_info "  ✓ podgen v2 编译成功"
}

# ── 主流程 ──
log_info "创建 Pod: rate=${RATE}/s, total=${TOTAL}, scheduler=${SCHED_NAME}, type=${WTYPE}"

auto_tune_params "$RATE"
build_podgen

# 构建 podgen 命令行
PODGEN_ARGS=(
  -rate "$RATE"
  -total "$TOTAL"
  -scheduler "$SCHED_NAME"
  -type "$WTYPE"
  -cpu "$CPU"
  -mem "$MEM"
  -namespace "$NAMESPACE"
  -image "$PAUSE_IMAGE"
  -workers "$WORKER_COUNT"
  -qps "$QPS"
  -burst "$BURST"
)

if [[ "$DRY_RUN" == "1" ]]; then
  PODGEN_ARGS+=(-dry-run)
fi

# burst 模式额外参数
if [[ "$WTYPE" == "burst" ]]; then
  PODGEN_ARGS+=(-burst-stages "200,500,1000,2000,1000,500,200" -stage-duration 10)
fi

# gang 模式额外参数
if [[ "$WTYPE" == "gang" ]]; then
  PODGEN_ARGS+=(-gang-size 5)
fi

START_TS=$(date +%s)

log_info "  启动 podgen v2: ${PODGEN_BIN} ${PODGEN_ARGS[*]}"
"$PODGEN_BIN" "${PODGEN_ARGS[@]}"

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

log_info "✓ Pod 创建完成: ${TOTAL} pods in $(format_duration $DURATION)"
log_info "  实际平均速率: $(( TOTAL / (DURATION > 0 ? DURATION : 1) )) pods/s"
