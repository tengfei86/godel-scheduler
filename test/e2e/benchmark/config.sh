#!/usr/bin/env bash
# config.sh — 全局配置（常量定义）
# 所有脚本通过 source config.sh 加载

set -eu

# ── 项目根目录 ──
_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_CONFIG_DIR/../../.." && pwd)"

# ── kind 集群 ──
KIND_CLUSTER_NAME="eno-bench"
KIND_CONFIG="${PROJECT_ROOT}/e2e-cluster/kind-config.yml"
KIND_KUBECONFIG="${HOME}/.kube/kind-${KIND_CLUSTER_NAME}"

# ── KWOK ──
KWOK_REPO="kubernetes-sigs/kwok"
NODE_TEMPLATE="${PROJECT_ROOT}/docs/performance/node.yaml"
KWOK_DEPLOY_SCRIPT="${PROJECT_ROOT}/docs/performance/deploy-kwok.sh"
NODE_CREATE_PARALLELISM=50

# ── 集群规模梯度 (S1–S5) ──
declare -A SCALE_NODES=(
  [s1]=100
  [s2]=1000
  [s3]=5000
  [s4]=10000
  [s5]=30000
)

# ── Scheduler 实例数梯度 (用于扩展性测试) ──
SCHEDULER_INSTANCE_COUNTS=(1 2 3 5)

# ── Prometheus ──
PROMETHEUS_ADDR="http://localhost:30090"
PROMETHEUS_NAMESPACE="monitoring"
PROMETHEUS_STEP="15s"
PROMETHEUS_QUERY_TIMEOUT="${PROMETHEUS_QUERY_TIMEOUT:-300}"  # 单次查询超时 (s)
PROMETHEUS_MAX_POINTS=11000                                  # 超过此数据点自动放大 step

# ── 镜像 ──
ENO_IMAGE="eno-local:latest"
GODEL_IMAGE="godel-local:latest"   # 原始 godel-scheduler 镜像（从上游 repo 构建）

# ── 上游 Gödel 源码 ──
GODEL_UPSTREAM_REPO="https://github.com/kubewharf/godel-scheduler.git"
GODEL_UPSTREAM_DIR="${TMPDIR:-/tmp}/godel-upstream"
PAUSE_IMAGE="registry.k8s.io/pause:3.9"

# ── 调度器配置 ──
ENO_NAMESPACE="eno-system"
GODEL_NAMESPACE="godel-system"     # 原始 godel-scheduler 命名空间
VOLCANO_NAMESPACE="volcano-system"
KOORDINATOR_NAMESPACE="koordinator-system"

# ── 调度器资源基线（用于跨组公平对比） ──
# 默认公平组: requests(1CPU/2G), limits(2CPU/4G)
# 极限组建议通过环境变量覆盖，例如:
#   export BENCH_SCHED_REQ_CPU=2 BENCH_SCHED_REQ_MEM=4G
#   export BENCH_SCHED_LIM_CPU=4 BENCH_SCHED_LIM_MEM=8G
BENCH_SCHED_REQ_CPU="${BENCH_SCHED_REQ_CPU:-2}"
BENCH_SCHED_REQ_MEM="${BENCH_SCHED_REQ_MEM:-4G}"
BENCH_SCHED_LIM_CPU="${BENCH_SCHED_LIM_CPU:-4}"
BENCH_SCHED_LIM_MEM="${BENCH_SCHED_LIM_MEM:-8G}"

# ── Binder 资源（默认继承 BENCH_SCHED_*，可独立覆盖） ──
BENCH_BINDER_REQ_CPU="${BENCH_BINDER_REQ_CPU:-${BENCH_SCHED_REQ_CPU}}"
BENCH_BINDER_REQ_MEM="${BENCH_BINDER_REQ_MEM:-${BENCH_SCHED_REQ_MEM}}"
BENCH_BINDER_LIM_CPU="${BENCH_BINDER_LIM_CPU:-${BENCH_SCHED_LIM_CPU}}"
BENCH_BINDER_LIM_MEM="${BENCH_BINDER_LIM_MEM:-${BENCH_SCHED_LIM_MEM}}"

# ── Dispatcher 资源（默认继承 BENCH_SCHED_*，可独立覆盖） ──
BENCH_DISPATCHER_REQ_CPU="${BENCH_DISPATCHER_REQ_CPU:-${BENCH_SCHED_REQ_CPU}}"
BENCH_DISPATCHER_REQ_MEM="${BENCH_DISPATCHER_REQ_MEM:-${BENCH_SCHED_REQ_MEM}}"
BENCH_DISPATCHER_LIM_CPU="${BENCH_DISPATCHER_LIM_CPU:-${BENCH_SCHED_LIM_CPU}}"
BENCH_DISPATCHER_LIM_MEM="${BENCH_DISPATCHER_LIM_MEM:-${BENCH_SCHED_LIM_MEM}}"

# ── 组标识 → schedulerName 映射 ──
declare -A SCHEDULER_NAMES=(
  [a]="eno-scheduler"     # 组 A 使用 ENO Embedded Binder
  [b]="godel-scheduler"   # 组 B 使用原始 godel-scheduler
  [c]="default-scheduler"
  [d]="volcano"
  [e]="koord-scheduler"
)

# ── 组标识 → 注解域映射 ──
declare -A ANNOTATION_DOMAINS=(
  [a]="eno.io"                # ENO 注解域
  [b]="godel.bytedance.com"   # 原始 godel 注解域
  [c]=""                      # kube-scheduler 无需
  [d]=""                      # Volcano 自有注解
  [e]=""                      # Koordinator 自有注解
)

# ── 组标识 → 部署方式描述 ──
declare -A GROUP_LABELS=(
  [a]="Embedded Binder (Proposed)"
  [b]="Gödel Scheduler (Baseline)"
  [c]="kube-scheduler (Reference)"
  [d]="Volcano"
  [e]="Koordinator"
)

# ── API Server 调优 ──
APISERVER_MAX_MUTATING_INFLIGHT=10000
APISERVER_MAX_REQUESTS_INFLIGHT=20000

# ── QPS/Burst ──
SCHEDULER_QPS=10000
SCHEDULER_BURST=10000

# ── 日志级别 ──
LOG_LEVEL=4

# ── 实验控制 ──
BENCH_NAMESPACE="bench"
COOLDOWN_SECONDS=30         # 清理后冷却等待
POLL_INTERVAL=5             # 轮询 Pending Pod 间隔
EXPERIMENT_REPEATS=3        # 每实验重复次数
WARMUP_EXCLUDE_SECONDS=60   # 剔除前 N 秒数据（冷启动）

# ── 超时 ──
WAIT_READY_TIMEOUT=300      # 等待组件就绪超时 (s)
WAIT_SCHEDULE_TIMEOUT=3600  # 等待所有 Pod 调度完成超时 (s)

# ── 结果输出 ──
RESULTS_DIR="${_CONFIG_DIR}/results"

# ── Manifests 路径 ──
MANIFESTS_BASE="${PROJECT_ROOT}/manifests/base"
MANIFESTS_GROUP_A="${PROJECT_ROOT}/manifests/overlays/embedded-binder"
MANIFESTS_EMBEDDED="${PROJECT_ROOT}/manifests/overlays/godel-scheduler"
MANIFESTS_MONITORING_BASE="${PROJECT_ROOT}/manifests/monitoring/base"

echo "[config] loaded — project_root=${PROJECT_ROOT}, cluster=${KIND_CLUSTER_NAME}"
