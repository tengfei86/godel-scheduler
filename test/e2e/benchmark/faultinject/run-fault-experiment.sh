#!/usr/bin/env bash
# run-fault-experiment.sh — 6.6 节故障注入专项实验的一键入口
#
# 只是对 run-experiment.sh 的薄封装，帮你把常用参数固化：
#   * 组     a (ENO)
#   * 规模   s3 (5000 节点)
#   * 负载   w2 (500 pods/s × 50K pods，未饱和)
#   * 实例   3 (inst3)
#   * 注入   layer0 或 layer3
#   * 时点   layer0: T+30s；layer3: T+10s (Lease 探测约需 45s，需给接管期留窗口)
#
# 用法:
#   ./run-fault-experiment.sh layer0 [run_id] [--fraction 0.1] [--from ...] [--to ...]
#   ./run-fault-experiment.sh layer3 [run_id]
#   ./run-fault-experiment.sh both   [--repeats 3]   # 依次跑 layer0×N 和 layer3×N
#
# 输出:
#   results/faultinject/<layer>/a_s3_w2_inst3/run<N>/
#     ├── inject-manifest.json / inject.log / inject-events.log / inject.rc
#     ├── invariant-i.txt
#     ├── metadata.txt
#     └── *.json  (Prometheus 时序)
#
# 事后:
#   python3 faultinject/fault-plot.py    <run_dir>
#   python3 faultinject/fault-summary.py <run_dir> --baseline <results/a/s3/w2/inst3/runX>

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${BENCHMARK_DIR}/config.sh"
source "${BENCHMARK_DIR}/lib/utils.sh"

usage() { grep -E '^# ' "$0" | sed 's/^# //'; exit 2; }
[[ $# -eq 0 ]] && usage

LAYER="$1"; shift
REPEATS=3
RUN_ID_ARG=""
INJECT_ARGS=""

case "$LAYER" in
  layer0|layer3) ;;
  both) ;;
  -h|--help) usage ;;
  *) log_error "第一参数必须是 layer0|layer3|both"; exit 2 ;;
esac

# 后续参数解析: [run_id]? 是数字则视为 run_id；其余转发给 inject 脚本
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repeats) REPEATS="$2"; shift 2 ;;
    --fraction|--from|--to|--target|--namespace)
      INJECT_ARGS+="${INJECT_ARGS:+ }$1 $2"; shift 2 ;;
    [1-9]|[1-9][0-9]) RUN_ID_ARG="$1"; shift ;;
    *) log_error "未知参数: $1"; exit 2 ;;
  esac
done

run_once() {
  local layer="$1" rid="$2"
  local logf="${RESULTS_DIR}/faultinject/${layer}/a_s3_w2_inst3/run${rid}/console.log"
  mkdir -p "$(dirname "$logf")"
  # Layer 3 走 Lease 心跳失活探测 (~45s)，注入必须提前才能让"存活实例接管"
  # 曲线完整落在 100s 的负载提交窗口内；Layer 0 拦截是即时的，保持 T+30s。
  local inject_at=30
  [[ "$layer" == "layer3" ]] && inject_at=10
  log_step "run-fault-experiment: layer=${layer} run=${rid} inject-at=T+${inject_at}s"
  # shellcheck disable=SC2086
  bash "${BENCHMARK_DIR}/run-experiment.sh" a s3 w2 "$rid" \
    --instances 3 \
    --inject "$layer" \
    --inject-at "$inject_at" \
    ${INJECT_ARGS:+--inject-args "$INJECT_ARGS"} \
    2>&1 | tee "$logf"
}

if [[ "$LAYER" == "both" ]]; then
  for i in $(seq 1 "$REPEATS"); do run_once layer0 "$i"; done
  for i in $(seq 1 "$REPEATS"); do run_once layer3 "$i"; done
else
  RUN_IDS=(${RUN_ID_ARG:-1 2 3})
  for r in "${RUN_IDS[@]}"; do run_once "$LAYER" "$r"; done
fi

separator "全部 fault-inject run 完成"
log_info "结果目录: ${RESULTS_DIR}/faultinject/"
log_info "接下来:"
log_info "  # 图与汇总"
log_info "  for d in ${RESULTS_DIR}/faultinject/*/*/run*/; do"
log_info "    python3 ${SCRIPT_DIR}/fault-plot.py    \"\$d\""
log_info "    python3 ${SCRIPT_DIR}/fault-summary.py \"\$d\""
log_info "  done"
