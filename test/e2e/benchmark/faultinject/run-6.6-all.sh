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
#   ./run-6.6-all.sh                     # 4 phase 全跑（默认 N=3, s2/w2/inst3）
#   ./run-6.6-all.sh --phase inject      # 仅跑注入
#   ./run-6.6-all.sh --phase preflight   # 仅前置检查
#   ./run-6.6-all.sh --phase analyze     # 仅分析（已有结果直接引用，不重跑）
#   ./run-6.6-all.sh --phase analyze --force-analyze  # 强制重跑分析
#   ./run-6.6-all.sh --repeats 5         # 每层跑 5 次
#   ./run-6.6-all.sh --fraction 0.2      # Layer 0 用 20% 漂移
#   ./run-6.6-all.sh --skip-baseline     # 不跑/不检查基线
#
# 论文默认场景是 s3/w2/inst3（5000 节点）；本脚本默认 s2/w2/inst3（1000 节点），
# 便于在中等 VM (≥32 GiB) 上直接复现。要跑论文完整场景请显式指定：
#   FI_SCALE=s3 FI_WORKLOAD=w2 FI_INSTANCES=3 ./run-6.6-all.sh
#
# 降规冒烟（用于 Mac 或更小机器，验证脚本能跑通）:
#   FI_SCALE=s1 FI_WORKLOAD=w1 FI_INSTANCES=3 ./run-6.6-all.sh --repeats 1
#
#   环境变量:
#     FI_SCALE      s1|s2|s3|s4  (默认 s2)
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
FORCE_ANALYZE=false
INJECT_ARGS=""
FI_SCALE="${FI_SCALE:-s2}"
FI_WORKLOAD="${FI_WORKLOAD:-w2}"
FI_INSTANCES="${FI_INSTANCES:-3}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)         PHASE="$2"; shift 2 ;;
    --repeats)       REPEATS="$2"; shift 2 ;;
    --skip-baseline) SKIP_BASELINE=true; shift ;;
    --force-analyze) FORCE_ANALYZE=true; shift ;;
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
    log_error "  修复: bash schedulers/deploy-group-a.sh --instances ${FI_INSTANCES}"
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
  local base="${RESULTS_DIR}/a/${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES}"
  # 早退：所有 3 个 run 都已完成时，phase 整体跳过（不打 separator，不打扰）
  local have=0
  for n in 1 2 3; do
    [[ -f "${base}/run${n}/metadata.txt" ]] && have=$((have + 1))
  done
  if (( have == 3 )); then
    log_info "Phase 2/4: baseline — 全部 3 个 run 已存在于 ${base}，跳过整个 phase"
    return 0
  fi

  separator "Phase 2/4: baseline — 无故障基线 (a/${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES}, 已有 ${have}/3)"
  if [[ "$SKIP_BASELINE" == "true" ]]; then
    log_info "  --skip-baseline 已指定，跳过"
    return 0
  fi
  local n
  for n in 1 2 3; do
    local d="${base}/run${n}"
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
  # 早退：所有 layer × N 都已完成
  local total=$((REPEATS * 2)) have=0 layer n d
  for layer in layer0 layer3; do
    for n in $(seq 1 "$REPEATS"); do
      [[ -f "${RESULTS_DIR}/faultinject/${layer}/${suffix}/run${n}/metadata.txt" ]] && have=$((have + 1))
    done
  done
  if (( have == total )); then
    log_info "Phase 3/4: inject — 全部 ${total} 个 run 已存在，跳过整个 phase"
    return 0
  fi

  separator "Phase 3/4: inject — 故障注入 (${suffix}, layer0 + layer3, ${REPEATS} 次；已有 ${have}/${total})"
  for layer in layer0 layer3; do
    for n in $(seq 1 "$REPEATS"); do
      d="${RESULTS_DIR}/faultinject/${layer}/${suffix}/run${n}"
      if [[ -f "${d}/metadata.txt" ]]; then
        log_info "  ✓ ${layer}/run${n} 已存在，跳过 (${d})"
        continue
      fi
      # Layer 3 走 Lease 心跳失活探测 (~45s)，注入必须提前才能让"存活实例接管"
      # 曲线完整落在负载提交窗口内；Layer 0 拦截是即时的，保持 T+30s。
      local inject_at=30
      [[ "$layer" == "layer3" ]] && inject_at=10
      log_step "inject ${layer} run ${n}/${REPEATS} (inject-at=T+${inject_at}s)"
      # shellcheck disable=SC2086
      if ! bash "${BENCHMARK_DIR}/run-experiment.sh" a "$FI_SCALE" "$FI_WORKLOAD" "$n" \
              --instances "$FI_INSTANCES" \
              --inject "$layer" \
              --inject-at "$inject_at" \
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
  separator "Phase 4/4: analyze — 出图 + 汇总 + 容错判定"
  local baseline="${RESULTS_DIR}/a/${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES}/run1"
  local baseline_arg=""
  [[ -f "${baseline}/metadata.txt" ]] && baseline_arg="--baseline ${baseline}"

  local ran=0 cached=0 verify_pass=0 verify_fail=0 rc=0 d
  shopt -s nullglob
  for d in "${RESULTS_DIR}"/faultinject/*/*/run*/; do
    [[ -f "${d}/inject-manifest.json" ]] || continue
    local vfile="${d}plots/verify.txt"

    # 幂等: plots/verify.txt 已存在且未强制重跑 → 直接引用旧结果
    if [[ -f "$vfile" && "$FORCE_ANALYZE" != "true" ]]; then
      cached=$((cached + 1))
      # 从 verify.txt 尾部取最终判定行
      if grep -q '✅' "$vfile" 2>/dev/null && ! grep -q '❌ FAIL' "$vfile" 2>/dev/null; then
        verify_pass=$((verify_pass + 1))
        log_info "  ✅ ${d} 已有分析 (cached)"
      else
        verify_fail=$((verify_fail + 1)); RC=3
        log_error "  ❌ ${d} 已有分析 (cached, 未通过)"
      fi
      continue
    fi

    log_step "analyze ${d}"
    python3 "${SCRIPT_DIR}/fault-plot.py"    "$d"               || rc=3
    python3 "${SCRIPT_DIR}/fault-summary.py" "$d" $baseline_arg || rc=3
    if python3 "${SCRIPT_DIR}/verify.py" "$d" >/dev/null; then
      verify_pass=$((verify_pass + 1))
      log_info "  ✅ 容错验证通过 (见 ${d}plots/verify.txt)"
    else
      verify_fail=$((verify_fail + 1)); RC=3
      log_error "  ❌ 容错验证未通过 (见 ${d}plots/verify.txt)"
    fi
    ran=$((ran + 1))
  done
  shopt -u nullglob

  if (( cached > 0 && ran == 0 && verify_fail == 0 )); then
    log_info "全部 ${cached} 个 run 都已有分析结果，直接引用（用 --force-analyze 强制重跑）"
  else
    log_info "analyze 完成: 新跑 ${ran}，复用 ${cached}；容错判定 pass=${verify_pass} fail=${verify_fail}"
  fi

  # 汇总: 逐个 run 打印一行结论
  if (( cached + ran > 0 )); then
    echo ""
    log_info "── 各 run 容错判定 ──"
    for d in "${RESULTS_DIR}"/faultinject/*/*/run*/; do
      local vf="${d}plots/verify.txt"
      [[ -f "$vf" ]] || continue
      local rel="${d#${RESULTS_DIR}/faultinject/}"; rel="${rel%/}"
      local verdict
      verdict=$(grep -E '^最终判定' "$vf" 2>/dev/null | head -1 | sed 's/^最终判定: //')
      echo "  ${rel}: ${verdict:-(missing verdict)}"
    done
  fi
  [[ $rc -eq 3 ]] && RC=3
}

# ── 主流程 ──
log_info "配置: scale=${FI_SCALE} workload=${FI_WORKLOAD} instances=${FI_INSTANCES} repeats=${REPEATS}"
if [[ "${FI_SCALE}/${FI_WORKLOAD}/${FI_INSTANCES}" != "s3/w2/3" ]]; then
  log_warn "当前配置为 ${FI_SCALE}/${FI_WORKLOAD}/inst${FI_INSTANCES}，非论文 6.6 节的 s3/w2/inst3；若要写入论文请补跑 s3"
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
