#!/usr/bin/env bash
# workloads/create-pods.sh — 按固定速率批量创建 Pod
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
# 示例:
#   ./create-pods.sh 500 50000 godel-scheduler 100 128
#   ./create-pods.sh 1000 10000 godel-scheduler 100 128 gang

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
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

log_info "创建 Pod: rate=${RATE}/s, total=${TOTAL}, scheduler=${SCHED_NAME}, type=${WTYPE}"

# ── 创建 namespace ──
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

# ── Volcano 非 gang 负载: 创建直通 PodGroup (minMember=1) ──
# gang 插件要求每个 Pod 关联 PodGroup，minMember=1 使其立即满足不阻塞调度
ensure_volcano_passthrough_pg() {
  if [[ "$SCHED_NAME" == "volcano" ]]; then
    log_info "  创建 Volcano 直通 PodGroup: bench-basic-pg (minMember=1)"
    kubectl apply -f - <<'EOF'
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: bench-basic-pg
  namespace: bench
spec:
  minMember: 1
EOF
  fi
}

# 根据调度器选择 basic 模板
select_basic_template() {
  if [[ "$SCHED_NAME" == "volcano" ]]; then
    echo "${TEMPLATE_DIR}/basic-pod-volcano.yaml.tpl"
  else
    echo "${TEMPLATE_DIR}/basic-pod.yaml.tpl"
  fi
}

# ── 速率控制核心函数 ──
# 将 batch_size 个 Pod YAML 拼接为多文档，单次 kubectl apply 提交
# 若 batch_size > MAX_PER_APPLY，则拆成多个并行 kubectl apply
MAX_PER_APPLY=500

# 精确 sleep: 补偿到 1 秒（需要 GNU date 或 macOS perl）
sleep_remaining() {
  local start_ns=$1
  local end_ns
  end_ns=$(date +%s%N 2>/dev/null || perl -MTime::HiRes=time -e 'printf "%d\n",time()*1e9')
  local elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  local remain_ms=$(( 1000 - elapsed_ms ))
  if (( remain_ms > 10 )); then
    sleep "$(awk "BEGIN{printf \"%.3f\", $remain_ms/1000}")"
  fi
}

# 渲染单个 Pod YAML（纯文本替换，避免 fork envsubst）
render_basic_pod() {
  local idx=$1 ns=$2 sched=$3 cpu=$4 mem=$5 image=$6 tpl=$7
  sed -e "s|\${INDEX}|${idx}|g" \
      -e "s|\${NAMESPACE}|${ns}|g" \
      -e "s|\${SCHEDULER_NAME}|${sched}|g" \
      -e "s|\${CPU}|${cpu}|g" \
      -e "s|\${MEM}|${mem}|g" \
      -e "s|\${PAUSE_IMAGE}|${image}|g" "$tpl"
}

# 批量提交一个 YAML 文件（可能包含多个文档）
apply_batch_file() {
  kubectl apply -f "$1" 2>/dev/null
}

# ── 生成并应用 Pod ──
create_basic_pods() {
  local rate=$1 total=$2 cpu=$3 mem=$4
  local template
  template=$(select_basic_template)
  ensure_volcano_passthrough_pg

  local batch_idx=0
  local global_idx=0
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local batch_file="${tmpdir}/batch.yaml"

  while (( global_idx < total )); do
    local tick_start
    tick_start=$(date +%s%N 2>/dev/null || perl -MTime::HiRes=time -e 'printf "%d\n",time()*1e9')

    # 本秒要创建的 Pod 数量
    local this_batch=$rate
    if (( global_idx + this_batch > total )); then
      this_batch=$((total - global_idx))
    fi

    # 拼接 YAML 到临时文件
    > "$batch_file"
    local sub_files=()
    local sub_idx=0
    local sub_count=0

    for i in $(seq 1 "$this_batch"); do
      global_idx=$((global_idx + 1))
      if (( sub_count > 0 )); then
        echo "---" >> "${tmpdir}/sub_${sub_idx}.yaml"
      fi
      render_basic_pod "$global_idx" "$NAMESPACE" "$SCHED_NAME" "$cpu" "$mem" "$PAUSE_IMAGE" "$template" \
        >> "${tmpdir}/sub_${sub_idx}.yaml"
      sub_count=$((sub_count + 1))

      if (( sub_count >= MAX_PER_APPLY )); then
        sub_files+=("${tmpdir}/sub_${sub_idx}.yaml")
        sub_idx=$((sub_idx + 1))
        sub_count=0
      fi
    done

    # 最后一个不满 MAX_PER_APPLY 的子文件
    if (( sub_count > 0 )); then
      sub_files+=("${tmpdir}/sub_${sub_idx}.yaml")
    fi

    # 并行提交所有子文件
    for f in "${sub_files[@]}"; do
      apply_batch_file "$f" &
    done
    wait

    # 清理子文件
    rm -f "${tmpdir}"/sub_*.yaml

    batch_idx=$((batch_idx + 1))
    if (( batch_idx % 10 == 0 )); then
      log_info "  进度: ${global_idx}/${total} ($((global_idx * 100 / total))%)"
    fi

    # 补偿 sleep 到 1 秒
    sleep_remaining "$tick_start"
  done
}

# ── 突发模式 (W5: 0→2000→0) ──
create_burst_pods() {
  local total=$1 cpu=$2 mem=$3
  local template
  template=$(select_basic_template)
  ensure_volcano_passthrough_pg

  # 阶梯式: 10s@200 → 10s@500 → 10s@1000 → 10s@2000 → 10s@1000 → 10s@500 → 10s@200
  local stages=(200 500 1000 2000 1000 500 200)
  local stage_duration=10
  local global_idx=0

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  for stage_rate in "${stages[@]}"; do
    log_info "  阶段: ${stage_rate} pods/s × ${stage_duration}s"

    for sec in $(seq 1 "$stage_duration"); do
      if (( global_idx >= total )); then break 2; fi

      local tick_start
      tick_start=$(date +%s%N 2>/dev/null || perl -MTime::HiRes=time -e 'printf "%d\n",time()*1e9')

      local this_batch=$stage_rate
      if (( global_idx + this_batch > total )); then
        this_batch=$((total - global_idx))
      fi

      # 拼接 + 分片提交
      local sub_idx=0 sub_count=0 sub_files=()
      for i in $(seq 1 "$this_batch"); do
        global_idx=$((global_idx + 1))
        if (( sub_count > 0 )); then
          echo "---" >> "${tmpdir}/sub_${sub_idx}.yaml"
        fi
        render_basic_pod "$global_idx" "$NAMESPACE" "$SCHED_NAME" "$cpu" "$mem" "$PAUSE_IMAGE" "$template" \
          >> "${tmpdir}/sub_${sub_idx}.yaml"
        sub_count=$((sub_count + 1))
        if (( sub_count >= MAX_PER_APPLY )); then
          sub_files+=("${tmpdir}/sub_${sub_idx}.yaml")
          sub_idx=$((sub_idx + 1)); sub_count=0
        fi
      done
      if (( sub_count > 0 )); then sub_files+=("${tmpdir}/sub_${sub_idx}.yaml"); fi

      for f in "${sub_files[@]}"; do apply_batch_file "$f" & done
      wait
      rm -f "${tmpdir}"/sub_*.yaml

      sleep_remaining "$tick_start"
    done
  done
}

# ── Gang 调度模式 (W6) ──
create_gang_pods() {
  local total=$1 cpu=$2 mem=$3
  local gang_size=5
  local groups=$((total / gang_size))
  local rate_groups=$((RATE / gang_size))
  (( rate_groups < 1 )) && rate_groups=1

  # 按调度器选择对应的 Gang 模板
  local template
  case "$SCHED_NAME" in
    volcano)
      template="${TEMPLATE_DIR}/gang-pod-volcano.yaml.tpl" ;;
    koord-scheduler)
      template="${TEMPLATE_DIR}/gang-pod-koordinator.yaml.tpl" ;;
    *)
      template="${TEMPLATE_DIR}/gang-pod.yaml.tpl" ;;
  esac

  # 从模板中分离 PodGroup 和 Pod 部分
  local pg_template pod_template
  pg_template=$(awk '/^---/{exit} {print}' "$template")
  pod_template=$(awk 'p{print} /^---/{p=1}' "$template")

  log_info "  Gang 模式: ${groups} groups × ${gang_size} pods/group, ${rate_groups} groups/s"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local group_idx=0

  while (( group_idx < groups )); do
    local tick_start
    tick_start=$(date +%s%N 2>/dev/null || perl -MTime::HiRes=time -e 'printf "%d\n",time()*1e9')

    local this_batch=$rate_groups
    if (( group_idx + this_batch > groups )); then
      this_batch=$((groups - group_idx))
    fi

    # 拼接本秒所有 PodGroup + Pod 到单个 YAML
    > "${tmpdir}/gang_batch.yaml"
    for g_offset in $(seq 1 "$this_batch"); do
      group_idx=$((group_idx + 1))
      # PodGroup
      echo "$pg_template" | sed \
        -e "s|\${GROUP_INDEX}|${group_idx}|g" \
        -e "s|\${GANG_SIZE}|${gang_size}|g" \
        -e "s|\${NAMESPACE}|${NAMESPACE}|g" \
        -e "s|\${SCHEDULER_NAME}|${SCHED_NAME}|g" \
        >> "${tmpdir}/gang_batch.yaml"
      echo "---" >> "${tmpdir}/gang_batch.yaml"
      # Member Pods
      for m in $(seq 1 "$gang_size"); do
        echo "$pod_template" | sed \
          -e "s|\${GROUP_INDEX}|${group_idx}|g" \
          -e "s|\${MEMBER_INDEX}|${m}|g" \
          -e "s|\${GANG_SIZE}|${gang_size}|g" \
          -e "s|\${NAMESPACE}|${NAMESPACE}|g" \
          -e "s|\${SCHEDULER_NAME}|${SCHED_NAME}|g" \
          -e "s|\${CPU}|${cpu}|g" \
          -e "s|\${MEM}|${mem}|g" \
          -e "s|\${PAUSE_IMAGE}|${PAUSE_IMAGE}|g" \
          >> "${tmpdir}/gang_batch.yaml"
        if (( m < gang_size )); then
          echo "---" >> "${tmpdir}/gang_batch.yaml"
        fi
      done
      if (( g_offset < this_batch )); then
        echo "---" >> "${tmpdir}/gang_batch.yaml"
      fi
    done

    apply_batch_file "${tmpdir}/gang_batch.yaml"
    rm -f "${tmpdir}/gang_batch.yaml"

    if (( group_idx % (rate_groups * 10) == 0 )); then
      log_info "  进度: ${group_idx}/${groups} groups"
    fi

    sleep_remaining "$tick_start"
  done
}

# ── 异构资源模式 (W7) ──
create_heterogeneous_pods() {
  local total=$1
  local template
  template=$(select_basic_template)
  ensure_volcano_passthrough_pg

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local global_idx=0

  while (( global_idx < total )); do
    local tick_start
    tick_start=$(date +%s%N 2>/dev/null || perl -MTime::HiRes=time -e 'printf "%d\n",time()*1e9')

    local this_batch=$RATE
    if (( global_idx + this_batch > total )); then
      this_batch=$((total - global_idx))
    fi

    # 拼接 + 分片提交
    local sub_idx=0 sub_count=0 sub_files=()
    for i in $(seq 1 "$this_batch"); do
      global_idx=$((global_idx + 1))

      # 30% 小(50m/64Mi), 40% 中(200m/256Mi), 20% 大(1000m/1Gi), 10% 超大(4000m/8Gi)
      local rand=$((RANDOM % 100))
      local cpu mem
      if (( rand < 30 )); then
        cpu=50; mem=64
      elif (( rand < 70 )); then
        cpu=200; mem=256
      elif (( rand < 90 )); then
        cpu=1000; mem=1024
      else
        cpu=4000; mem=8192
      fi

      if (( sub_count > 0 )); then
        echo "---" >> "${tmpdir}/sub_${sub_idx}.yaml"
      fi
      render_basic_pod "$global_idx" "$NAMESPACE" "$SCHED_NAME" "$cpu" "$mem" "$PAUSE_IMAGE" "$template" \
        >> "${tmpdir}/sub_${sub_idx}.yaml"
      sub_count=$((sub_count + 1))
      if (( sub_count >= MAX_PER_APPLY )); then
        sub_files+=("${tmpdir}/sub_${sub_idx}.yaml")
        sub_idx=$((sub_idx + 1)); sub_count=0
      fi
    done
    if (( sub_count > 0 )); then sub_files+=("${tmpdir}/sub_${sub_idx}.yaml"); fi

    for f in "${sub_files[@]}"; do apply_batch_file "$f" & done
    wait
    rm -f "${tmpdir}"/sub_*.yaml

    if (( global_idx % (RATE * 10) == 0 )); then
      log_info "  进度: ${global_idx}/${total} ($((global_idx * 100 / total))%)"
    fi

    sleep_remaining "$tick_start"
  done
}

# ── 根据类型分发 ──
START_TS=$(date +%s)

case "$WTYPE" in
  basic)
    create_basic_pods "$RATE" "$TOTAL" "$CPU" "$MEM"
    ;;
  burst)
    create_burst_pods "$TOTAL" "$CPU" "$MEM"
    ;;
  gang)
    create_gang_pods "$TOTAL" "$CPU" "$MEM"
    ;;
  heterogeneous)
    create_heterogeneous_pods "$TOTAL"
    ;;
  *)
    log_error "未知负载类型: ${WTYPE}"
    exit 1
    ;;
esac

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

log_info "✓ Pod 创建完成: ${TOTAL} pods in $(format_duration $DURATION)"
log_info "  实际速率: $(( TOTAL / (DURATION > 0 ? DURATION : 1) )) pods/s"
