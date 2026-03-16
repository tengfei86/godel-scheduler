#!/usr/bin/env bash
# workloads/create-pods.sh — 按固定速率批量创建 Pod
#
# 底层使用 Go 编写的 podgen 工具，解决 bash 循环 fork/exec
# 导致的速率不稳定问题。
#
# 用法:
#   ./create-pods.sh <rate> <total> <scheduler_name> [cpu] [mem] [workload_type]
#
# 参数:
#   rate            - 每秒创建的 Pod 数量
#   total           - 总 Pod 数量
#   scheduler_name  - schedulerName (godel-scheduler|default-scheduler|volcano|koord-scheduler)
#   cpu             - CPU 请求 (millicores, 默认 100)
#   mem             - 内存请求 (Mi, 默认 128)
#   workload_type   - basic|burst|gang|heterogeneous (默认 basic)
#
# 负载场景说明:
#   w1 - 低负载稳态       100 pods/s,  10K pods, cpu:100m/mem:128Mi
#   w2 - 中负载稳态       500 pods/s,  50K pods, cpu:100m/mem:128Mi
#   w3 - 高负载稳态     1,000 pods/s, 100K pods, cpu:100m/mem:128Mi
#   w4 - 极限负载       2,000 pods/s, 200K pods, cpu:100m/mem:128Mi
#   w5 - 突发洪峰   0→2000→0 pods/s,  50K pods, cpu:100m/mem:128Mi
#   w6 - Gang 调度   200 groups/s × 5 pods/group, 10K pods
#   w7 - 异构资源       500 pods/s,  50K pods, 混合规格(30%小+40%中+20%大+10%超大)
#   w8 - 大规模集群   2,000 pods/s, 800K pods, cpu:100m/mem:128Mi
#
# 环境变量 (可选):
#   PODGEN_BATCH    - 每次 kubectl apply 的 Pod 数 (默认 200)
#   PODGEN_WORKERS  - 并发 kubectl apply 的 worker 数 (默认 8)
#   PODGEN_DRY_RUN  - 设为 1 则仅打印 YAML 不提交
#
# 示例:
#   ./create-pods.sh 500 50000 godel-scheduler 100 128
#   ./create-pods.sh 1000 10000 godel-scheduler 100 128 gang
#   PODGEN_WORKERS=16 ./create-pods.sh 2000 200000 godel-scheduler

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
BATCH_SIZE="${PODGEN_BATCH:-200}"
WORKER_COUNT="${PODGEN_WORKERS:-8}"
DRY_RUN="${PODGEN_DRY_RUN:-0}"

# ── 自动调参 ──
# 根据速率自动调整 batch 和 workers，确保管道不堵塞
auto_tune_params() {
  local r=$1

  # batch_size: 速率越高，每批越大，减少 kubectl 调用次数
  # 经验公式: batch ≈ rate / workers，但不超过 500，不低于 50
  if [[ "$BATCH_SIZE" == "200" ]]; then  # 仅在用户未设置时自动调参
    local auto_batch=$(( r / WORKER_COUNT ))
    (( auto_batch < 50 )) && auto_batch=50
    (( auto_batch > 500 )) && auto_batch=500
    BATCH_SIZE=$auto_batch
  fi

  # workers: 速率 >= 1000 时自动加到 16
  if [[ "$WORKER_COUNT" == "8" ]]; then
    if (( r >= 2000 )); then
      WORKER_COUNT=20
    elif (( r >= 1000 )); then
      WORKER_COUNT=16
    elif (( r >= 500 )); then
      WORKER_COUNT=12
    fi
  fi

  log_info "  调参: batch=${BATCH_SIZE}, workers=${WORKER_COUNT}"
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

  log_info "  编译 podgen..."
  if ! command -v go &>/dev/null; then
    log_error "未找到 go 编译器，请安装 Go 1.21+"
    log_error "  或手动编译: cd ${PODGEN_DIR} && go build -o podgen ."
    exit 1
  fi

  (cd "$PODGEN_DIR" && CGO_ENABLED=0 go build -o podgen .) || {
    log_error "podgen 编译失败"
    exit 1
  }
  log_info "  ✓ podgen 编译成功"
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
  -batch "$BATCH_SIZE"
  -workers "$WORKER_COUNT"
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

log_info "  启动 podgen: ${PODGEN_BIN} ${PODGEN_ARGS[*]}"
"$PODGEN_BIN" "${PODGEN_ARGS[@]}"

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

log_info "✓ Pod 创建完成: ${TOTAL} pods in $(format_duration $DURATION)"
log_info "  实际平均速率: $(( TOTAL / (DURATION > 0 ? DURATION : 1) )) pods/s"
