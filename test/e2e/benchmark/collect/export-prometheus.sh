#!/usr/bin/env bash
# collect/export-prometheus.sh — 从 Prometheus API 导出时间序列 JSON
#
# 用法:
#   ./export-prometheus.sh <group> <start_ts> <end_ts> <output_dir>
#
# 按组选择不同的 PromQL 查询集:
#   A:   Gödel Shared Binder 指标名
#   B:   Gödel Embedded Binder 指标名
#   C:   kube-scheduler 指标名
#   D:   Volcano 指标名
#   E:   Koordinator 指标名

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/prometheus.sh"

GROUP="${1:?用法: export-prometheus.sh <group> <start_ts> <end_ts> <output_dir>}"
START="${2:?缺少参数: start_ts}"
END="${3:?缺少参数: end_ts}"
DIR="${4:?缺少参数: output_dir}"

mkdir -p "$DIR"

log_info "导出 Prometheus 数据: group=${GROUP}, range=[${START}, ${END}], dir=${DIR}"

# ═══════════════════════════════════════════════
# 通用查询（所有组共享）
# ═══════════════════════════════════════════════
declare -A COMMON_QUERIES=(
  # Pending Pods
  [pending_pods]='sum(scheduler_pending_pods)'
)

# ═══════════════════════════════════════════════
# Gödel 查询集（组 A: Shared Binder）
# ═══════════════════════════════════════════════
declare -A GODEL_SHARED_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='sum(rate(scheduler_pod_scheduling_attempts{result="scheduled"}[1m]))'
  [bind_throughput_pods]='sum(rate(binder_binding_pod_attempts{result="success"}[1m]))'
  [bind_throughput_units]='sum(rate(binder_unit_e2e_duration_seconds_count[1m]))'

  # 调度延迟
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_e2e_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_e2e_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_e2e_scheduling_duration_seconds_bucket[1m]))by(le))'

  # 绑定延迟
  [bind_latency_p50]='histogram_quantile(0.50,sum(rate(binder_pod_binding_phase_duration_seconds_bucket{phase="binding"}[1m]))by(le))'
  [bind_latency_p90]='histogram_quantile(0.90,sum(rate(binder_pod_binding_phase_duration_seconds_bucket{phase="binding"}[1m]))by(le))'
  [bind_latency_p99]='histogram_quantile(0.99,sum(rate(binder_pod_binding_phase_duration_seconds_bucket{phase="binding"}[1m]))by(le))'

  # 核心算法延迟
  [algorithm_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket[1m]))by(le))'
  [algorithm_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket[1m]))by(le))'

  # 成功率
  [scheduling_success_rate]='(sum(rate(scheduler_pod_scheduling_attempts{result="scheduled"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_pod_scheduling_attempts[5m])), 1e-9)'
  [scheduling_error_rate]='(sum(rate(scheduler_pod_scheduling_attempts{result="error"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_pod_scheduling_attempts[5m])), 1e-9)'

  # Goroutines
  [goroutines]='sum(scheduler_goroutines) by (work)'

  # 队列等待
  [queue_wait_p90]='histogram_quantile(0.90,rate(scheduler_pod_pending_in_queue_duration_seconds_bucket[5m]))'
)

# ═══════════════════════════════════════════════
# Gödel 查询集（组 B: Embedded Binder）
# ═══════════════════════════════════════════════
declare -A GODEL_EMBEDDED_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='sum(rate(scheduler_pod_scheduling_attempts{result="scheduled"}[1m]))'
  [bind_throughput_pods]='sum(rate(binder_embedded_bind_pods_total{result="success"}[1m]))'
  [bind_throughput_units]='sum(rate(binder_embedded_bind_total{result="success"}[1m]))'

  # 调度延迟
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_e2e_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_e2e_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_e2e_scheduling_duration_seconds_bucket[1m]))by(le))'

  # 绑定延迟
  [bind_latency_p50]='histogram_quantile(0.50,sum(rate(binder_embedded_bind_pod_duration_seconds_bucket[1m]))by(le))'
  [bind_latency_p90]='histogram_quantile(0.90,sum(rate(binder_embedded_bind_pod_duration_seconds_bucket[1m]))by(le))'
  [bind_latency_p99]='histogram_quantile(0.99,sum(rate(binder_embedded_bind_pod_duration_seconds_bucket[1m]))by(le))'

  # 核心算法延迟
  [algorithm_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket[1m]))by(le))'
  [algorithm_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket[1m]))by(le))'

  # 成功率
  [scheduling_success_rate]='(sum(rate(scheduler_pod_scheduling_attempts{result="scheduled"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_pod_scheduling_attempts[5m])), 1e-9)'
  [scheduling_error_rate]='(sum(rate(scheduler_pod_scheduling_attempts{result="error"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_pod_scheduling_attempts[5m])), 1e-9)'

  # Embedded Binder 特有
  [bind_inflight]='binder_embedded_bind_inflight'
  [bind_retries]='sum(rate(binder_embedded_bind_retries_total[5m]))'
  [dispatcher_fallback]='sum(rate(binder_dispatcher_fallback_total[5m]))'
  [node_validation_failures]='sum(rate(binder_node_validation_failures_total[5m]))'

  # Goroutines
  [goroutines]='sum(scheduler_goroutines) by (work)'

  # 队列等待
  [queue_wait_p90]='histogram_quantile(0.90,rate(scheduler_pod_pending_in_queue_duration_seconds_bucket[5m]))'
)

# ═══════════════════════════════════════════════
# kube-scheduler 查询集（组 C）
# ═══════════════════════════════════════════════
declare -A KUBE_QUERIES=(
  [scheduling_throughput]='sum(rate(scheduler_pod_scheduling_duration_seconds_count[1m]))'
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket[1m]))by(le))'
  [scheduling_attempts_total]='sum(rate(scheduler_pod_scheduling_attempts_total[1m])) by (result)'
  [queue_wait_p90]='histogram_quantile(0.90,rate(scheduler_pending_pods_bucket[5m]))'
  [goroutines]='go_goroutines{job="kube-scheduler"}'
)

# ═══════════════════════════════════════════════
# Volcano 查询集（组 D）
# ═══════════════════════════════════════════════
declare -A VOLCANO_QUERIES=(
  [scheduling_throughput]='sum(rate(volcano_scheduler_schedule_count{status="success"}[1m]))'
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(volcano_scheduler_schedule_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(volcano_scheduler_schedule_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(volcano_scheduler_schedule_duration_seconds_bucket[1m]))by(le))'
  [scheduling_error_rate]='sum(rate(volcano_scheduler_schedule_count{status="error"}[5m]))/sum(rate(volcano_scheduler_schedule_count[5m]))'
  [pending_pods]='volcano_scheduler_unschedule_task_count'
  [goroutines]='go_goroutines{job=~".*volcano.*"}'
)

# ═══════════════════════════════════════════════
# Koordinator 查询集（组 E）
# ═══════════════════════════════════════════════
declare -A KOORDINATOR_QUERIES=(
  [scheduling_throughput]='sum(rate(scheduler_pod_scheduling_duration_seconds_count{job=~".*koord.*"}[1m]))'
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [scheduling_attempts]='sum(rate(scheduler_pod_scheduling_attempts_total{job=~".*koord.*"}[1m])) by (result)'
  [goroutines]='go_goroutines{job=~".*koord.*"}'
)

# ═══════════════════════════════════════════════
# 按组选择查询集并导出
# ═══════════════════════════════════════════════
export_queries() {
  local -n queries=$1
  local count=0
  local total=${#queries[@]}

  for name in "${!queries[@]}"; do
    count=$((count + 1))
    local query="${queries[$name]}"
    local output="${DIR}/${name}.json"

    log_debug "  [${count}/${total}] ${name}"
    prometheus_query_range "$query" "$START" "$END" "$output"
  done
}

# 通用查询
log_info "导出通用查询..."
export_queries COMMON_QUERIES

# 按组导出
case "$GROUP" in
  a)
    log_info "导出 Gödel Shared Binder 查询集 (${#GODEL_SHARED_QUERIES[@]} 条)..."
    export_queries GODEL_SHARED_QUERIES
    ;;
  b)
    log_info "导出 Gödel Embedded Binder 查询集 (${#GODEL_EMBEDDED_QUERIES[@]} 条)..."
    export_queries GODEL_EMBEDDED_QUERIES
    ;;
  c)
    log_info "导出 kube-scheduler 查询集 (${#KUBE_QUERIES[@]} 条)..."
    export_queries KUBE_QUERIES
    ;;
  d)
    log_info "导出 Volcano 查询集 (${#VOLCANO_QUERIES[@]} 条)..."
    export_queries VOLCANO_QUERIES
    ;;
  e)
    log_info "导出 Koordinator 查询集 (${#KOORDINATOR_QUERIES[@]} 条)..."
    export_queries KOORDINATOR_QUERIES
    ;;
  *)
    log_error "未知组: ${GROUP}"
    exit 1
    ;;
esac

log_info "✓ Prometheus 数据导出完成 → ${DIR}/"
ls -la "$DIR"/*.json 2>/dev/null | wc -l | xargs -I {} echo "  共 {} 个 JSON 文件"
