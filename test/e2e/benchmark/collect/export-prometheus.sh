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
declare -A GODEL_QUERIES=(
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
  [queue_wait_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_pending_in_queue_duration_seconds_bucket[5m]))by(le))'
)

# ═══════════════════════════════════════════════
# Gödel 查询集（组 B: Embedded Binder）
# ═══════════════════════════════════════════════
declare -A ENO_EMBEDDED_QUERIES=(
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
  [bind_inflight]='sum(binder_embedded_bind_inflight)'
  [bind_retries]='sum(rate(binder_embedded_bind_retries_total[5m]))'
  [dispatcher_fallback]='sum(rate(binder_dispatcher_fallback_total[5m]))'
  [node_validation_failures]='sum(rate(binder_node_validation_failures_total[5m]))'

  # Goroutines
  [goroutines]='sum(scheduler_goroutines) by (work)'

  # 队列等待
  [queue_wait_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_pending_in_queue_duration_seconds_bucket[5m]))by(le))'
)

# ═══════════════════════════════════════════════
# kube-scheduler 查询集（组 C）
# ═══════════════════════════════════════════════
declare -A KUBE_QUERIES=(
  # 吞吐量 — scheduler_schedule_attempts_total{result} 是 counter
  [scheduling_throughput]='sum(rate(scheduler_schedule_attempts_total{result="scheduled"}[1m]))'
  [scheduling_attempts_by_result]='sum(rate(scheduler_schedule_attempts_total[1m])) by (result)'

  # 调度延迟 — scheduler_scheduling_attempt_duration_seconds (算法耗时)
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_scheduling_attempt_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_scheduling_attempt_duration_seconds_bucket[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_scheduling_attempt_duration_seconds_bucket[1m]))by(le))'

  # E2E SLI 延迟 — scheduler_pod_scheduling_sli_duration_seconds (K8s 1.28+)
  [sli_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_pod_scheduling_sli_duration_seconds_bucket[1m]))by(le))'
  [sli_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_scheduling_sli_duration_seconds_bucket[1m]))by(le))'
  [sli_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_pod_scheduling_sli_duration_seconds_bucket[1m]))by(le))'

  # 核心算法延迟
  [algorithm_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket[1m]))by(le))'
  [algorithm_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket[1m]))by(le))'

  # 成功率
  [scheduling_success_rate]='(sum(rate(scheduler_schedule_attempts_total{result="scheduled"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_schedule_attempts_total[5m])), 1e-9)'
  [scheduling_error_rate]='(sum(rate(scheduler_schedule_attempts_total{result="error"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_schedule_attempts_total[5m])), 1e-9)'

  # Pending pods (gauge)
  [pending_pods]='sum(scheduler_pending_pods)'

  # Goroutines — kube-scheduler 单实例，无需聚合
  [goroutines]='scheduler_goroutines'

  # 队列入队速率
  [queue_incoming_pods]='sum(rate(scheduler_queue_incoming_pods_total[1m])) by (event)'
)

# ═══════════════════════════════════════════════
# Volcano 查询集（组 D）
# ═══════════════════════════════════════════════
declare -A VOLCANO_QUERIES=(
  # 吞吐量 — per-job(PodGroup) 完成调度的速率
  # Volcano 每个 job 触发 2 次 Observe，需除以 2 修正
  [scheduling_throughput]='sum(rate(volcano_e2e_job_scheduling_latency_milliseconds_count[1m])) / 2'
  # 调度循环吞吐量 (sessions/s)
  [session_throughput]='sum(rate(volcano_e2e_scheduling_latency_milliseconds_count[1m]))'

  # E2E 调度延迟（原始单位毫秒，转换为秒）
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(volcano_e2e_scheduling_latency_milliseconds_bucket[1m]))by(le))/1000'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(volcano_e2e_scheduling_latency_milliseconds_bucket[1m]))by(le))/1000'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(volcano_e2e_scheduling_latency_milliseconds_bucket[1m]))by(le))/1000'

  # Action 级别调度延迟
  [action_latency_p90]='histogram_quantile(0.90,sum(rate(volcano_action_scheduling_latency_milliseconds_bucket[1m]))by(le,action))/1000'
  [action_latency_p99]='histogram_quantile(0.99,sum(rate(volcano_action_scheduling_latency_milliseconds_bucket[1m]))by(le,action))/1000'

  # Task 调度延迟
  [task_latency_p90]='histogram_quantile(0.90,sum(rate(volcano_task_scheduling_latency_milliseconds_bucket[1m]))by(le))/1000'
  [task_latency_p99]='histogram_quantile(0.99,sum(rate(volcano_task_scheduling_latency_milliseconds_bucket[1m]))by(le))/1000'

  # Plugin 延迟
  [plugin_latency_p90]='histogram_quantile(0.90,sum(rate(volcano_plugin_scheduling_latency_milliseconds_bucket[1m]))by(le,plugin))/1000'

  # 成功率 — Volcano 无 Pod 级 result 标签，用 Job 调度完成数 / (完成数 + 不可调度数) 近似
  [scheduling_success_rate]='(sum(rate(volcano_e2e_job_scheduling_latency_milliseconds_count[5m])) / 2 or on() vector(0)) / clamp_min(sum(rate(volcano_e2e_job_scheduling_latency_milliseconds_count[5m])) / 2 + sum(rate(volcano_unschedule_task_count[5m])), 1e-9)'
  # 错误率 — 用不可调度任务数变化率
  [scheduling_error_rate]='sum(rate(volcano_unschedule_task_count[5m]))'

  # Pending（不可调度任务/Job 数）— 必须 sum() 聚合，否则裸指标会返回数千条 per-task 时间序列
  [pending_pods]='sum(volcano_unschedule_task_count)'
  [unschedule_jobs]='sum(volcano_unschedule_job_count)'

  # Goroutines
  [goroutines]='go_goroutines{job=~".*volcano.*"}'

  # E2E Job scheduling duration (Gauge, 每个 Job 一条, 单位毫秒 → 聚合为统计值，除以 1000 转秒)
  [job_scheduling_duration_avg]='avg(volcano_e2e_job_scheduling_duration) / 1000'
  [job_scheduling_duration_max]='max(volcano_e2e_job_scheduling_duration) / 1000'
)

# ═══════════════════════════════════════════════
# Koordinator 查询集（组 E）
# ═══════════════════════════════════════════════
declare -A KOORDINATOR_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='sum(rate(scheduler_pod_scheduling_duration_seconds_count{job=~".*koord.*"}[1m]))'
  [scheduling_attempts]='sum(rate(scheduler_schedule_attempts_total{job=~".*koord.*"}[1m])) by (result)'

  # E2E 调度延迟
  [scheduling_latency_p50]='histogram_quantile(0.50,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [scheduling_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [scheduling_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_pod_scheduling_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'

  # 核心算法延迟
  [algorithm_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [algorithm_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_scheduling_algorithm_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'

  # 调度尝试延迟 (含 binding)
  [attempt_latency_p90]='histogram_quantile(0.90,sum(rate(scheduler_scheduling_attempt_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'
  [attempt_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_scheduling_attempt_duration_seconds_bucket{job=~".*koord.*"}[1m]))by(le))'

  # 扩展点延迟（使用 5m 窗口减少计算开销，避免大规模 Pod 时 Prometheus 超时）
  [extension_point_latency_p99]='histogram_quantile(0.99,sum(rate(scheduler_framework_extension_point_duration_seconds_bucket{job=~".*koord.*"}[5m]))by(le,extension_point))'

  # 节点评估数
  [evaluated_nodes_avg]='sum(rate(scheduler_pod_scheduling_evaluated_nodes_sum{job=~".*koord.*"}[1m]))/sum(rate(scheduler_pod_scheduling_evaluated_nodes_count{job=~".*koord.*"}[1m]))'
  [feasible_nodes_avg]='sum(rate(scheduler_pod_scheduling_feasible_nodes_sum{job=~".*koord.*"}[1m]))/sum(rate(scheduler_pod_scheduling_feasible_nodes_count{job=~".*koord.*"}[1m]))'

  # 队列
  [queue_incoming_pods]='sum(rate(scheduler_queue_incoming_pods_total{job=~".*koord.*"}[1m])) by (event)'

  # Goroutines & Pending — Koordinator 通常单实例，label 维度少，无需额外聚合
  [goroutines]='go_goroutines{job=~".*koord.*"}'
  [pending_pods]='scheduler_pending_pods{job=~".*koord.*"}'

  # 成功率
  [scheduling_success_rate]='(sum(rate(scheduler_schedule_attempts_total{result="scheduled",job=~".*koord.*"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_schedule_attempts_total{job=~".*koord.*"}[5m])), 1e-9)'
  [scheduling_error_rate]='(sum(rate(scheduler_schedule_attempts_total{result="error",job=~".*koord.*"}[5m])) or on() vector(0)) / clamp_min(sum(rate(scheduler_schedule_attempts_total{job=~".*koord.*"}[5m])), 1e-9)'

  # 抢占
  [preemption_attempts]='sum(rate(scheduler_preemption_attempts_total{job=~".*koord.*"}[1m]))'
)

# ═══════════════════════════════════════════════
# 按组选择查询集并导出
# ═══════════════════════════════════════════════
export_queries() {
  local -n queries=$1
  local skip_ref="${2:-}"
  local count=0
  local total=${#queries[@]}

  for name in "${!queries[@]}"; do
    # 如果指定了 skip_ref（组专属查询集），跳过组专属已覆盖的 key
    if [[ -n "$skip_ref" ]]; then
      local -n skip_set=$skip_ref
      if [[ -v "skip_set[$name]" ]]; then
        log_debug "  跳过 ${name}（组专属已覆盖）"
        continue
      fi
    fi

    count=$((count + 1))
    local query="${queries[$name]}"
    local output="${DIR}/${name}.json"

    log_debug "  [${count}/${total}] ${name}"
    prometheus_query_range "$query" "$START" "$END" "$output"
  done
}

# 按组导出
case "$GROUP" in
  a)
    log_info "导出通用查询..."
    export_queries COMMON_QUERIES ENO_EMBEDDED_QUERIES
    log_info "导出 ENO Embedded Binder 查询集 (${#ENO_EMBEDDED_QUERIES[@]} 条)..."
    export_queries ENO_EMBEDDED_QUERIES
    ;;
  b)
    log_info "导出通用查询..."
    export_queries COMMON_QUERIES GODEL_QUERIES
    log_info "导出 Gödel Shared Binder 查询集 (${#GODEL_QUERIES[@]} 条)..."
    export_queries GODEL_QUERIES
    ;;
  c)
    log_info "导出通用查询..."
    export_queries COMMON_QUERIES KUBE_QUERIES
    log_info "导出 kube-scheduler 查询集 (${#KUBE_QUERIES[@]} 条)..."
    export_queries KUBE_QUERIES
    ;;
  d)
    log_info "导出通用查询..."
    export_queries COMMON_QUERIES VOLCANO_QUERIES
    log_info "导出 Volcano 查询集 (${#VOLCANO_QUERIES[@]} 条)..."
    export_queries VOLCANO_QUERIES
    ;;
  e)
    log_info "导出通用查询..."
    export_queries COMMON_QUERIES KOORDINATOR_QUERIES
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
