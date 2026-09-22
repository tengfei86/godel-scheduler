#!/usr/bin/env bash
# collect/export-prometheus.sh — 从 Prometheus API 导出时间序列 JSON
#
# 用法:
#   ./export-prometheus.sh <group> <start_ts> <end_ts> <output_dir>
#
# 按组选择不同的 PromQL 查询集:
#   A:   ENO Embedded Binder 指标名（proposed）
#   B:   Gödel Shared Binder 指标名（baseline）
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
# Gödel 查询集（组 B: Shared Binder）
# 直接引用 prometheus-config.yaml recording rules 中的 godel:* 预计算指标
# ═══════════════════════════════════════════════
declare -A GODEL_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='godel:scheduler_pod_scheduling_attempts:rate1m'
  [scheduling_peak_throughput]='godel:scheduler_peak_throughput:30m'
  [bind_throughput_pods]='godel:binder_binding_pod_attempts:rate1m'

  # 调度延迟
  [scheduling_latency_p50]='godel:scheduler_e2e_scheduling_duration:p50'
  [scheduling_latency_p90]='godel:scheduler_e2e_scheduling_duration:p90'
  [scheduling_latency_p99]='godel:scheduler_e2e_scheduling_duration:p99'
  [scheduling_latency_avg]='godel:scheduler_e2e_scheduling_duration:avg'

  # 绑定延迟（Pod 级别，binding phase）
  [bind_latency_p50]='godel:binder_pod_binding_phase_duration:p50'
  [bind_latency_p90]='godel:binder_pod_binding_phase_duration:p90'
  [bind_latency_p99]='godel:binder_pod_binding_phase_duration:p99'
  [bind_latency_avg]='godel:binder_pod_binding_phase_duration:avg'

  # Unit E2E 延迟（binder → done）
  [bind_unit_latency_p90]='godel:binder_unit_e2e_duration:p90'
  [bind_unit_latency_p99]='godel:binder_unit_e2e_duration:p99'

  # 核心算法延迟
  [algorithm_latency_p90]='godel:scheduler_scheduling_algorithm_duration:p90'
  [algorithm_latency_p99]='godel:scheduler_scheduling_algorithm_duration:p99'

  # 绑定成功率
  [bind_success_rate]='godel:binder_binding_pod_attempts:success_rate1m'

  # 错误计数
  [bind_rejection_rate]='godel:binder_pod_rejection:rate1m'
  [bind_failure_rate]='godel:binder_pod_binding_failure:rate1m'

  # Pod E2E 延迟（dispatcher → scheduler → binder → done）
  [pod_e2e_latency_p50]='godel:pod_e2e_duration:p50'
  [pod_e2e_latency_p90]='godel:pod_e2e_duration:p90'
  [pod_e2e_latency_p99]='godel:pod_e2e_duration:p99'

  # Schedule + Bind 合并延迟估算
  [e2e_combined_p90]='godel:e2e_schedule_and_bind_duration:p90_estimate'
  [e2e_combined_p99]='godel:e2e_schedule_and_bind_duration:p99_estimate'

  # Goroutines
  [goroutines]='sum(scheduler_goroutines) by (work)'

  # 队列等待
  [queue_wait_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_pending_in_queue_duration_seconds_bucket[1m]))by(le))'
)

# ═══════════════════════════════════════════════
# ENO 查询集（组 A: Embedded Binder）
# 直接引用 prometheus-config.yaml recording rules 中的 eno:* 预计算指标
# ═══════════════════════════════════════════════
declare -A ENO_EMBEDDED_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='eno:scheduler_pod_scheduling_attempts:rate1m'
  [scheduling_peak_throughput]='eno:scheduler_peak_throughput:30m'
  [bind_throughput_pods]='eno:binder_embedded_bind_pods:rate1m'
  [bind_throughput_units]='eno:binder_embedded_bind_units:rate1m'

  # 调度延迟
  [scheduling_latency_p50]='eno:scheduler_e2e_scheduling_duration:p50'
  [scheduling_latency_p90]='eno:scheduler_e2e_scheduling_duration:p90'
  [scheduling_latency_p99]='eno:scheduler_e2e_scheduling_duration:p99'
  [scheduling_latency_avg]='eno:scheduler_e2e_scheduling_duration:avg'

  # 绑定延迟（Pod 级别）
  [bind_latency_p50]='eno:binder_embedded_bind_pod_duration:p50'
  [bind_latency_p90]='eno:binder_embedded_bind_pod_duration:p90'
  [bind_latency_p99]='eno:binder_embedded_bind_pod_duration:p99'
  [bind_latency_avg]='eno:binder_embedded_bind_pod_duration:avg'

  # 绑定延迟（Unit 级别）
  [bind_unit_latency_p50]='eno:binder_embedded_bind_duration:p50'
  [bind_unit_latency_p90]='eno:binder_embedded_bind_duration:p90'
  [bind_unit_latency_p99]='eno:binder_embedded_bind_duration:p99'
  [bind_unit_latency_avg]='eno:binder_embedded_bind_duration:avg'

  # 核心算法延迟
  [algorithm_latency_p90]='eno:scheduler_scheduling_algorithm_duration:p90'
  [algorithm_latency_p99]='eno:scheduler_scheduling_algorithm_duration:p99'

  # 绑定成功率
  [bind_success_rate]='eno:binder_embedded_bind_pods:success_rate1m'
  [bind_unit_success_rate]='eno:binder_embedded_bind_units:success_rate1m'

  # Embedded Binder 特有指标
  [bind_retries]='eno:binder_embedded_bind_retries:rate1m'
  [dispatcher_fallback]='eno:binder_dispatcher_fallback:rate1m'
  [node_validation_failures]='eno:binder_node_validation_failures:rate1m'
  [bind_inflight]='sum(binder_embedded_bind_inflight)'

  # 故障注入专项 (6.6 节): 按 Scheduler Pod 拆分的时序
  [bind_success_by_pod]='eno:binder_embedded_bind_pods:success_rate1m_by_pod'
  [dispatcher_fallback_by_pod]='eno:binder_dispatcher_fallback:rate1m_by_pod'
  [node_validation_failures_by_pod]='eno:binder_node_validation_failures:rate1m_by_pod'

  # Pod E2E 延迟（dispatcher → scheduler → binder → done）
  [pod_e2e_latency_p50]='eno:pod_e2e_duration:p50'
  [pod_e2e_latency_p90]='eno:pod_e2e_duration:p90'
  [pod_e2e_latency_p99]='eno:pod_e2e_duration:p99'

  # Schedule + Bind 合并延迟估算
  [e2e_combined_p90]='eno:e2e_schedule_and_bind_duration:p90_estimate'
  [e2e_combined_p99]='eno:e2e_schedule_and_bind_duration:p99_estimate'

  # Goroutines
  [goroutines]='sum(scheduler_goroutines) by (work)'

  # 队列等待
  [queue_wait_p90]='histogram_quantile(0.90,sum(rate(scheduler_pod_pending_in_queue_duration_seconds_bucket[1m]))by(le))'
)

# ═══════════════════════════════════════════════
# kube-scheduler 查询集（组 C）
# 直接引用 prometheus-config.yaml recording rules 中的 kube:* 预计算指标
# ═══════════════════════════════════════════════
declare -A KUBE_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='kube:scheduler_schedule_attempts_scheduled:rate1m'
  [scheduling_throughput_by_result]='kube:scheduler_schedule_attempts:rate1m'
  [scheduling_peak_throughput]='kube:scheduler_peak_throughput:30m'

  # 调度尝试延迟（Filter+Score+Bind 全程）
  [scheduling_latency_p50]='kube:scheduler_scheduling_attempt_duration:p50'
  [scheduling_latency_p90]='kube:scheduler_scheduling_attempt_duration:p90'
  [scheduling_latency_p99]='kube:scheduler_scheduling_attempt_duration:p99'
  [scheduling_latency_avg]='kube:scheduler_scheduling_attempt_duration:avg'

  # E2E SLI 延迟（入队 → Bound，K8s 1.28+）
  [sli_latency_p50]='kube:scheduler_pod_scheduling_sli_duration:p50'
  [sli_latency_p90]='kube:scheduler_pod_scheduling_sli_duration:p90'
  [sli_latency_p99]='kube:scheduler_pod_scheduling_sli_duration:p99'
  [sli_latency_avg]='kube:scheduler_pod_scheduling_sli_duration:avg'

  # 核心算法延迟（Filter+Score only）
  [algorithm_latency_p90]='kube:scheduler_scheduling_algorithm_duration:p90'
  [algorithm_latency_p99]='kube:scheduler_scheduling_algorithm_duration:p99'

  # Per-pod 调度尝试次数分布
  [pod_scheduling_attempts_p90]='kube:scheduler_pod_scheduling_attempts:p90'
  [pod_scheduling_attempts_p99]='kube:scheduler_pod_scheduling_attempts:p99'

  # 成功率 / 错误率
  [scheduling_success_rate]='kube:scheduler_schedule_attempts:success_rate1m'
  [scheduling_error_rate]='kube:scheduler_schedule_attempts:error_rate1m'

  # Framework extension point 延迟
  [extension_point_latency_p90]='kube:scheduler_framework_extension_point_duration:p90'
  [extension_point_latency_p99]='kube:scheduler_framework_extension_point_duration:p99'

  # Plugin 执行延迟
  [plugin_latency_p90]='kube:scheduler_plugin_execution_duration:p90'

  # Pending pods（直接查原始 gauge）
  [pending_pods]='sum(scheduler_pending_pods)'

  # Goroutines
  [goroutines]='scheduler_goroutines'
)

# ═══════════════════════════════════════════════
# Volcano 查询集（组 D）
# 直接引用 prometheus-config.yaml recording rules 中的 volcano:* 预计算指标
# ═══════════════════════════════════════════════
declare -A VOLCANO_QUERIES=(
  # 吞吐量（tasks/s，Assumed stage = 成功放置）
  [scheduling_throughput]='volcano:scheduling_throughput:rate1m'
  [session_throughput]='volcano:session_throughput:rate1m'
  [scheduling_peak_throughput]='volcano:scheduling_peak_throughput:30m'

  # E2E 调度延迟（单位已转换为秒）
  [scheduling_latency_p50]='volcano:e2e_scheduling_latency:p50_seconds'
  [scheduling_latency_p90]='volcano:e2e_scheduling_latency:p90_seconds'
  [scheduling_latency_p99]='volcano:e2e_scheduling_latency:p99_seconds'
  [scheduling_latency_avg]='volcano:e2e_scheduling_latency:avg_seconds'

  # Action 级别调度延迟
  [action_latency_p90]='volcano:action_scheduling_latency:p90_seconds'
  [action_latency_p99]='volcano:action_scheduling_latency:p99_seconds'

  # Task 调度延迟
  [task_latency_p90]='volcano:task_scheduling_latency:p90_seconds'
  [task_latency_p99]='volcano:task_scheduling_latency:p99_seconds'

  # Plugin 延迟
  [plugin_latency_p90]='volcano:plugin_scheduling_latency:p90_seconds'

  # 不可调度速率
  [unschedule_task_rate]='volcano:unschedule_task_rate:1m'

  # Pending（直接查原始 gauge）
  [pending_pods]='sum(volcano_unschedule_task_count)'
  [unschedule_jobs]='sum(volcano_unschedule_job_count)'

  # Goroutines（sum() 防御性聚合，避免未来多副本时 series 分裂）
  [goroutines]='sum(go_goroutines{job=~".*volcano.*"})'
)

# ═══════════════════════════════════════════════
# Koordinator 查询集（组 E）
# 直接引用 prometheus-config.yaml recording rules 中的 koord:* 预计算指标
# ═══════════════════════════════════════════════
declare -A KOORDINATOR_QUERIES=(
  # 吞吐量
  [scheduling_throughput]='koord:scheduler_schedule_attempts_scheduled:rate1m'
  [scheduling_throughput_by_result]='koord:scheduler_schedule_attempts:rate1m'
  [scheduling_peak_throughput]='koord:scheduler_peak_throughput:30m'

  # 调度尝试延迟（Filter+Score+Bind 全程）
  [scheduling_latency_p50]='koord:scheduler_scheduling_attempt_duration:p50'
  [scheduling_latency_p90]='koord:scheduler_scheduling_attempt_duration:p90'
  [scheduling_latency_p99]='koord:scheduler_scheduling_attempt_duration:p99'
  [scheduling_latency_avg]='koord:scheduler_scheduling_attempt_duration:avg'

  # Pod E2E SLI 延迟（入队 → Bound）
  [sli_latency_p50]='koord:scheduler_pod_scheduling_sli_duration:p50'
  [sli_latency_p90]='koord:scheduler_pod_scheduling_sli_duration:p90'
  [sli_latency_p99]='koord:scheduler_pod_scheduling_sli_duration:p99'
  [sli_latency_avg]='koord:scheduler_pod_scheduling_sli_duration:avg'

  # 核心算法延迟（Filter+Score only）
  [algorithm_latency_p90]='koord:scheduler_scheduling_algorithm_duration:p90'
  [algorithm_latency_p99]='koord:scheduler_scheduling_algorithm_duration:p99'

  # Framework extension point 延迟
  [extension_point_latency_p90]='koord:scheduler_framework_extension_point_duration:p90'

  # Plugin 执行延迟
  [plugin_latency_p90]='koord:scheduler_plugin_execution_duration:p90'

  # 成功率 / 错误率
  [scheduling_success_rate]='koord:scheduler_schedule_attempts:success_rate1m'
  [scheduling_error_rate]='koord:scheduler_schedule_attempts:error_rate1m'

  # Pending pods（sum() 聚合 pod 副本，保留 queue 维度供分队列显示）
  [pending_pods]='sum(scheduler_pending_pods{job=~".*koord.*"}) by (queue)'

  # Goroutines（sum() 聚合 pod 副本）
  [goroutines]='sum(go_goroutines{job=~".*koord.*"})'
)

# ═══════════════════════════════════════════════
# run 级累计直方图分位（短 run 专用，仅组 A/B）
# ═══════════════════════════════════════════════
# 背景：时序分位 recording rule 基于 rate(..._bucket[1m])，run 时长不足约 2 分钟时，
# query_range 只能导出 0~1 个采样点（w6 Gang 实测单次 run 仅 29~39 s），按第 6 章
# 口径（去首尾各 2 点）会得到空值。
#
# 这里换一条独立路径：用 increase() 在整个 run 窗口上取累计增量，再交给
# histogram_quantile 计算分位。每个被处理的 Pod 都计入样本，不依赖滑窗长度。
#
# 注意不要用「首尾两次快照相减」的写法（(x @ end()) - (x @ start())）：
# 逐 run 重部署调度器时，进程在 Step 6 之后才开始产生样本，@ start() 处取不到
# 样本，整个表达式会返回空结果。2026-09-15 的 s2/w2 批次（--redeploy-each-run）
# 四个 run_* 查询全部为空即由此而来。increase() 只依赖窗口内已有的样本，
# 且其外推只是把各 bucket 同比缩放，不影响 histogram_quantile 的取值。
#
# 输出 run_<metric>.json，格式与其余导出文件一致（matrix，通常 1 个点，位于窗口末端）。
# 尾部留 RUN_TAIL_MARGIN 秒余量以覆盖最后一次 scrape。
export_run_totals() {
  local pod_e2e_bucket="${1:?用法: export_run_totals <pod_e2e_bucket>}"
  local margin="${RUN_TAIL_MARGIN:-30}"
  local query_end=$(( END + margin ))
  local span=$(( query_end - START ))
  if (( span < 60 )); then
    span=60
  fi
  # step = span：query_range 只评估窗口末端一个点，前一个点（窗口完全落在 run
  # 之前）自然为空，不参与统计
  local step="${span}s"

  local sched_bucket="scheduler_e2e_scheduling_duration_seconds_bucket"

  declare -A run_queries=(
    [run_scheduling_latency_p90]="histogram_quantile(0.90, sum by (le)(increase(${sched_bucket}[${span}s])))"
    [run_scheduling_latency_p99]="histogram_quantile(0.99, sum by (le)(increase(${sched_bucket}[${span}s])))"
    [run_pod_e2e_latency_p90]="histogram_quantile(0.90, sum by (le)(increase(${pod_e2e_bucket}[${span}s])))"
    [run_pod_e2e_latency_p99]="histogram_quantile(0.99, sum by (le)(increase(${pod_e2e_bucket}[${span}s])))"
  )

  log_info "导出 run 级累计直方图分位 (window=[${START}, ${query_end}], span=${span}s)..."
  for name in "${!run_queries[@]}"; do
    local output="${DIR}/${name}.json"
    prometheus_query_range "${run_queries[$name]}" "$START" "$query_end" "$output" "$step"
    # 逐条回显取值：查询"成功但为空"时不会再静默通过
    local got
    got=$(jq -r 'if (.data.result | length) == 0 then "空(无样本)"
                 else ([.data.result[].values[-1][1]] | last) end' "$output" 2>/dev/null || echo "解析失败")
    if [[ "$got" == "空(无样本)" || "$got" == "解析失败" ]]; then
      log_warn "  ${name} = ${got}（该 run 的延迟将记为无数据）"
    else
      log_info "  ${name} = ${got}"
    fi
  done
}

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
    export_run_totals "eno_pod_e2e_duration_seconds_bucket"
    ;;
  b)
    log_info "导出通用查询..."
    export_queries COMMON_QUERIES GODEL_QUERIES
    log_info "导出 Gödel Shared Binder 查询集 (${#GODEL_QUERIES[@]} 条)..."
    export_queries GODEL_QUERIES
    export_run_totals "godel_pod_e2e_duration_seconds_bucket"
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
