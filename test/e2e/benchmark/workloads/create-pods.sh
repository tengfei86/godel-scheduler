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

# ── 生成并应用 Pod ──
create_basic_pods() {
  local rate=$1 total=$2 cpu=$3 mem=$4
  local batch_count=0
  local template
  template=$(select_basic_template)
  ensure_volcano_passthrough_pg

  for i in $(seq 1 "$total"); do
    export INDEX="$i"
    export NAMESPACE="$NAMESPACE"
    export SCHEDULER_NAME="$SCHED_NAME"
    export CPU="$cpu"
    export MEM="$mem"
    export PAUSE_IMAGE="${PAUSE_IMAGE}"

    envsubst < "$template" | kubectl apply -f - &

    batch_count=$((batch_count + 1))
    if (( batch_count >= rate )); then
      wait
      batch_count=0
      sleep 1
      if (( i % (rate * 10) == 0 )); then
        log_info "  进度: ${i}/${total} ($(( i * 100 / total ))%)"
      fi
    fi
  done
  wait
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
  local idx=0

  for stage_rate in "${stages[@]}"; do
    log_info "  阶段: ${stage_rate} pods/s × ${stage_duration}s"
    local stage_total=$((stage_rate * stage_duration))
    local batch_count=0

    for j in $(seq 1 "$stage_total"); do
      idx=$((idx + 1))
      if (( idx > total )); then
        break 2
      fi

      export INDEX="$idx"
      export NAMESPACE="$NAMESPACE"
      export SCHEDULER_NAME="$SCHED_NAME"
      export CPU="$cpu"
      export MEM="$mem"
      export PAUSE_IMAGE="${PAUSE_IMAGE}"

      envsubst < "$template" | kubectl apply -f - &

      batch_count=$((batch_count + 1))
      if (( batch_count >= stage_rate )); then
        wait
        batch_count=0
        sleep 1
      fi
    done
    wait
  done
  wait
}

# ── Gang 调度模式 (W6) ──
create_gang_pods() {
  local total=$1 cpu=$2 mem=$3
  local gang_size=5
  local groups=$((total / gang_size))
  local rate_groups=$((RATE / gang_size))  # 每秒创建的 PodGroup 数

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

  local batch_count=0

  log_info "  Gang 模式: ${groups} groups × ${gang_size} pods/group (template: $(basename "$template"))"

  for g in $(seq 1 "$groups"); do
    for m in $(seq 1 "$gang_size"); do
      export GROUP_INDEX="$g"
      export MEMBER_INDEX="$m"
      export GANG_SIZE="$gang_size"
      export NAMESPACE="$NAMESPACE"
      export SCHEDULER_NAME="$SCHED_NAME"
      export CPU="$cpu"
      export MEM="$mem"
      export PAUSE_IMAGE="${PAUSE_IMAGE}"

      envsubst < "$template" | kubectl apply -f - &
    done

    batch_count=$((batch_count + 1))
    if (( batch_count >= rate_groups )); then
      wait
      batch_count=0
      sleep 1
      if (( g % (rate_groups * 10) == 0 )); then
        log_info "  进度: ${g}/${groups} groups"
      fi
    fi
  done
  wait
}

# ── 异构资源模式 (W7) ──
create_heterogeneous_pods() {
  local total=$1
  local template
  template=$(select_basic_template)
  ensure_volcano_passthrough_pg
  local batch_count=0

  # 30% 小(50m/64Mi), 40% 中(200m/256Mi), 20% 大(1000m/1Gi), 10% 超大(4000m/8Gi)
  for i in $(seq 1 "$total"); do
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

    export INDEX="$i"
    export NAMESPACE="$NAMESPACE"
    export SCHEDULER_NAME="$SCHED_NAME"
    export CPU="$cpu"
    export MEM="$mem"
    export PAUSE_IMAGE="${PAUSE_IMAGE}"

    envsubst < "$template" | kubectl apply -f - &

    batch_count=$((batch_count + 1))
    if (( batch_count >= RATE )); then
      wait
      batch_count=0
      sleep 1
      if (( i % (RATE * 10) == 0 )); then
        log_info "  进度: ${i}/${total} ($(( i * 100 / total ))%)"
      fi
    fi
  done
  wait
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
