#!/usr/bin/env bash
# run-6.6-all.sh — 论文 6.6 节的一键复现入口
#
# 组织形式:
#   一个脚本对应 6.6 节的完整实验流水线，分 4 个 phase：
#     preflight  → 校验集群、组 a 三实例、Prometheus recording rule 已加载
#     baseline   → 若 results/a/s3/w2/inst3/run{1,2,3} 缺失，补跑无故障基线
#     inject     → layer0 × N 与 layer3 × N（N 默认为 3）
#     analyze    → 对每个 run 目录跑 fault-plot.py 与 fault-summary.py
#
# 每个 phase 都是幂等的：baseline 若已存在则跳过；inject 若 run 目录已含
# metadata.txt 则跳过；analyze 每次都重跑（成本低）。
#
# 用法:
#   ./run-6.6-all.sh                     # 4 phase 全跑（默认 N=3, s3/w2/inst3, 论文配置）
#   ./run-6.6-all.sh --phase inject      # 仅跑注入
#   ./run-6.6-all.sh --phase preflight   # 仅前置检查
#   ./run-6.6-all.sh --repeats 5         # 每层跑 5 次
#   ./run-6.6-all.sh --fraction 0.2      # Layer 0 用 20% 漂移
#   ./run-6.6-all.sh --skip-baseline     # 不跑/不检查基线
#
# 降规冒烟（用于 Mac 或资源受限环境，验证脚本能跑通，不作论文数据）:
#   FI_SCALE=s1 FI_WORKLOAD=w1 FI_INSTANCES=3 ./run-6.6-all.sh --repeats 1
#
#   环境变量:
#     FI_SCALE      s1|s2|s3|s4  (默认 s3)
#     FI_WORKLOAD   w1..w7       (默认 w2)
#     FI_INSTANCES  1|2|3|5      (默认 3)
#
# 事后:
#   结果: results/faultinject/{layer0,layer3}/a_s3_w2_inst3/run<N>/
#   图  : 上述目录下的 plots/{layer0,layer3}-timeseries.png
#   汇总: 同目录下 plots/summary.txt
#
# 退出码:
#   0 全部成功
#   2 前置校验失败（不会继续）
#   3 某个 run 失败（其余 run 仍继续，最终以 3 结束）

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${BENCHMARK_DIR}/../../.." && pwd)"
source "${BENCHMARK_DIR}/config.sh"
source "${BENCHMARK_DIR}/lib/utils.sh"

# ── 参数（--scale/--workload/--instances 可用 FI_* 环境变量覆盖）──
PHASE="all"
REPEATS=3
SKIP_BASELINE=false
INJECT_ARGS=""
FI_SCALE="${FI_SCALE:-s3}"
FI_WORKLOAD="${FI_WORKLOAD:-w2}"
FI_INSTANCES="${FI_INSTANCES:-3}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)         PHASE="$2"; shift 2 ;;
    --repeats)       REPEATS="$2"; shift 2 ;;
    --skip-baseline) SKIP_BASELINE=true; shift ;;
    --fraction|--from|--to|--target)
      INJECT_ARGS+="${INJECT_ARGS:+ }$1 $2"; shift 2 ;;
    -h|--help) grep -E '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) log_error "未知参数: $1"; exit 2 ;;
  esac
done

case "$PHASE" in
  all|preflight|baseline|inject|analyze) ;;
  *) log_error "无效 --phase: ${PHASE} (可选: all|preflight|baseline|inject|analyze)"; exit 2 ;;
esac

RC=0

# ═══════════════════════════════════════════════
# Phase 1: preflight
# ═══════════════════════════════════════════════
phase_preflight() {
  separator "Phase 1/4: preflight — 前置检查"
  local fail=0

  # (1) kubectl 可用 & 集群通
  if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "kubectl 无法连接集群 (kubeconfig=${KUBECONFIG:-~/.kube/config})"
    fail=1
  else
    log_info "✓ kubectl 集群可达"
  fi

  # (2) 节点数 = FI_SCALE
  local nodes want="${SCALE_NODES[$FI_SCALE]}"
  nodes=$(kubectl get nodes -l fake.byted.org/node --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if (( nodes != want )); then
    log_error "KWOK 节点数不匹配: 实际 ${nodes}, 期望 ${want} (${FI_SCALE})"
    log_error "  修复: bash setup-cluster.sh ${FI_SCALE}   或   run-experiment.sh 加 --setup-nodes"
    fail=1
  else
    log_info "✓ KWOK 节点数 = ${nodes} (${FI_SCALE})"
  fi

  # (3) 组 a N 副本 Running
  local sched_pods
  sched_pods=$(kubectl get pods -n "${ENO_NAMESPACE}" -l app=eno-scheduler \
                --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if (( sched_pods < FI_INSTANCES )); then
    log_error "eno-scheduler Running 副本数 = ${sched_pods}, 期望 ≥ ${FI_INSTANCES}"
    log_error "  修复: bash schedulers/scale-schedulers.sh a ${FI_INSTANCES}"
    fail=1
  else
    log_info "✓ eno-scheduler 副本 = ${sched_pods}"
  fi

  # (4) 每个实例都有唯一 --eno-scheduler-name
  local unique_names
  unique_names=$(kubectl get pods -n "${ENO_NAMESPACE}" -l app=eno-scheduler \
                  -o jsonpath='{range .items[*]}{.metadata.labels.eno-scheduler-name}{"\n"}{end}' \
                  2>/dev/null | sort -u | wc -l | tr -d ' ')
  if (( unique_names < FI_INSTANCES )); then
    log_error "各实例 eno-scheduler-name label 未唯一化（只有 ${unique_names} 种，期望 ${FI_INSTANCES}）"
    log_error "  修复: 使用 scale-schedulers.sh 部署（会为每个实例设置 --eno-scheduler-name=eno-scheduler-N）"
    fail=1
  else
    log_info "✓ 实例名唯一 (${unique_names} 种)"
  fi

  # (5) Prometheus 里 by-pod recording rule 已加载
  local rule_body rule_hit
  rule_body=$(curl -sfm 5 "${PROMETHEUS_ADDR}/api/v1/rules" 2>/dev/null || true)
  if [[ -z "$rule_body" ]]; then
    rule_hit=0
  else
    rule_hit=$(printf '%s' "$rule_body" | grep -c 'binder_dispatcher_fallback:rate1m_by_pod' || true)
  fi
  rule_hit=${rule_hit:-0}
  if (( rule_hit == 0 )); then
    log_error "Prometheus 未加载 by-pod recording rule"
    log_error "  修复: kubectl apply -f ${PROJECT_ROOT}/manifests/monitoring/overlays/group-a/prometheus-config.yaml"
    log_error "        kubectl -n monitoring rollout restart deploy/prometheus"
    fail=1
  else
    log_info "✓ Prometheus recording rules 已加载"
  fi

  # (6) inject 脚本可执行
  for f in inject-layer0.sh inject-layer3.sh assert-invariant-i.sh; do
    if [[ ! -x "${SCRIPT_DIR}/${f}" ]]; then
      log_error "脚本不可执行: ${f}"; fail=1
    fi
  done

  if (( fail )); then
    log_error "preflight 未通过，请先修复上述问题"
    return 2
  fi
  log_info "preflight 通过"
  return 0
}

# ═══════════════════════════════════════════════
# Phase 2: baseline
# ═══════════════════════════════════════════════
phase_baseline() {
  separator "Phase 2/4: baseline — 无故障基线 (a/${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES})"
  if [[ "$SKIP_BASELINE" == "true" ]]; then
    log_info "  --skip-baseline 已指定，跳过"
    return 0
  fi
  local n
  for n in $(seq 1 3); do
    local d="${RESULTS_DIR}/a/${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES}/run${n}"
    if [[ -f "${d}/metadata.txt" ]]; then
      log_info "  ✓ run${n} 已存在，跳过 (${d})"
      continue
    fi
    log_step "baseline run ${n}/3"
    if ! bash "${BENCHMARK_DIR}/run-experiment.sh" a "$FI_SCALE" "$FI_WORKLOAD" "$n" --instances "$FI_INSTANCES"; then
      log_error "baseline run ${n} 失败"
      RC=3
    fi
  done
}

# ═══════════════════════════════════════════════
# Phase 3: inject
# ═══════════════════════════════════════════════
phase_inject() {
  local suffix="a_${FI_SCALE}_${FI_WORKLOAD}_inst${FI_INSTANCES}"
  separator "Phase 3/4: inject — 故障注入 (${suffix}, layer0 + layer3, ${REPEATS} 次)"
  local layer n d
  for layer in layer0 layer3; do
    for n in $(seq 1 "$REPEATS"); do
      d="${RESULTS_DIR}/faultinject/${layer}/${suffix}/run${n}"
      if [[ -f "${d}/metadata.txt" ]]; then
        log_info "  ✓ ${layer}/run${n} 已存在，跳过 (${d})"
        continue
      fi
      log_step "inject ${layer} run ${n}/${REPEATS}"
      # shellcheck disable=SC2086
      if ! bash "${BENCHMARK_DIR}/run-experiment.sh" a "$FI_SCALE" "$FI_WORKLOAD" "$n" \
              --instances "$FI_INSTANCES" \
              --inject "$layer" \
              --inject-at 30 \
              ${INJECT_ARGS:+--inject-args "$INJECT_ARGS"}; then
        log_error "${layer}/run${n} 失败"
        RC=3
      fi
    done
  done
}

# ═══════════════════════════════════════════════
# Phase 4: analyze
# ═══════════════════════════════════════════════
phase_analyze() {
  separator "Phase 4/4: analyze — 出图 + 汇总"
  local baseline="${RESULTS_DIR}/a/${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES}/run1"
  local baseline_arg=""
  [[ -f "${baseline}/metadata.txt" ]] && baseline_arg="--baseline ${baseline}"

  local ok=0 fail=0 d
  shopt -s nullglob
  for d in "${RESULTS_DIR}"/faultinject/*/*/run*/; do
    [[ -f "${d}/inject-manifest.json" ]] || continue
    log_step "analyze ${d}"
    if python3 "${SCRIPT_DIR}/fault-plot.py"    "$d" \
       && python3 "${SCRIPT_DIR}/fault-summary.py" "$d" $baseline_arg; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1)); RC=3
    fi
  done
  shopt -u nullglob
  log_info "analyze 完成: ok=${ok} fail=${fail}"
}

# ── 主流程 ──
log_info "配置: scale=${FI_SCALE} workload=${FI_WORKLOAD} instances=${FI_INSTANCES} repeats=${REPEATS}"
if [[ "${FI_SCALE}/${FI_WORKLOAD}/${FI_INSTANCES}" != "s3/w2/3" ]]; then
  log_warn "非论文默认配置 (s3/w2/inst3)，产出数据仅用于脚本验证，不作论文数据"
fi

case "$PHASE" in
  all)
    phase_preflight || exit $?
    phase_baseline
    phase_inject
    phase_analyze
    ;;
  preflight) phase_preflight || exit $? ;;
  baseline)  phase_baseline ;;
  inject)    phase_inject ;;
  analyze)   phase_analyze ;;
esac

separator "6.6 全流程结束 (rc=${RC})"
exit "$RC"
