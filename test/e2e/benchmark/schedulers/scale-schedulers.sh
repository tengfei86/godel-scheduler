#!/usr/bin/env bash
# schedulers/scale-schedulers.sh — 动态调整 Gödel Scheduler 实例数量
#
# 将基础 "scheduler" deployment 缩容到 0，然后创建 N 个独立的
# scheduler-0, scheduler-1, ..., scheduler-(N-1) 实例。
# 每个实例拥有独立的 --eno-scheduler-name、端口和 hostNetwork。
#
# 用法:
#   ./scale-schedulers.sh <instance_count> [--embedded-binder]
#
# 参数:
#   instance_count    正整数，Scheduler 实例数量
#   --embedded-binder 为每个实例启用内嵌 Binder 模式（组 B）
#
# 示例:
#   ./scale-schedulers.sh 3                    # 3 个 Scheduler (共享 Binder)
#   ./scale-schedulers.sh 5 --embedded-binder  # 5 个 Scheduler (内嵌 Binder)
#
# 端口方案 (hostNetwork):
#   scheduler-i: --port=$((10251 + i*1000)), --secure-port=$((10959 + i*1000))

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cluster.sh"

COUNT="${1:?用法: scale-schedulers.sh <instance_count> [--embedded-binder]}"
shift

EMBEDDED_BINDER=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --embedded-binder) EMBEDDED_BINDER=true; shift ;;
    *)                 log_error "未知参数: $1"; exit 1 ;;
  esac
done

if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
  log_error "实例数必须为正整数: $COUNT"
  exit 1
fi

log_info "调整 Scheduler 实例数: ${COUNT} (embedded-binder=${EMBEDDED_BINDER})"

# ── Step 1: 缩容基础 scheduler deployment ──
if kubectl get deployment scheduler -n "${ENO_NAMESPACE}" >/dev/null 2>&1; then
  log_info "缩容基础 scheduler deployment 到 0"
  kubectl scale deployment scheduler -n "${ENO_NAMESPACE}" --replicas=0
fi

# ── Step 2: 删除已有的 scheduler-* deployment ──
existing=$(kubectl get deployment -n "${ENO_NAMESPACE}" --no-headers 2>/dev/null \
  | awk '{print $1}' | grep "^scheduler-" || true)
for deploy in $existing; do
  log_info "删除: ${deploy}"
  kubectl delete deployment "$deploy" -n "${ENO_NAMESPACE}" --ignore-not-found
done

# ── Step 3: 生成并应用 N 个 Scheduler Deployment ──
generate_scheduler_yaml() {
  local idx="$1"
  local name="scheduler-${idx}"
  local sched_name="eno-scheduler-${idx}"
  local port=$((10251 + idx * 1000))
  local secure_port=$((10959 + idx * 1000))

  cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  namespace: ${ENO_NAMESPACE}
  labels:
    component: scheduler
spec:
  replicas: 1
  selector:
    matchLabels:
      eno-scheduler-name: ${sched_name}
  template:
    metadata:
      labels:
        eno-scheduler-name: ${sched_name}
        app: eno-scheduler
        component: scheduler
    spec:
      hostNetwork: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      serviceAccountName: eno
      tolerations:
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: scheduler
          image: ${ENO_IMAGE}
          imagePullPolicy: Never
          command: ["/usr/local/bin/scheduler"]
          args:
            - --leader-elect=false
            - --tracer=noop
            - --v=4
            - --disable-preemption=false
            - --config=/config/scheduler.config
            - --reservation-ttl=60
            - --feature-gates=ResourceReservation=true
            - --secure-port=${secure_port}
            - --eno-scheduler-name=${sched_name}
            - --port=${port}
YAML

  if [[ "${EMBEDDED_BINDER}" == "true" ]]; then
    cat <<YAML
            - --enable-embedded-binder=true
            - --max-bind-retries=3
            - --bind-timeout=30s
            - --max-local-retries=5
YAML
  fi

  cat <<YAML
          ports:
            - containerPort: ${port}
              name: metrics
              protocol: TCP
          resources:
            requests:
              cpu: "${BENCH_SCHED_REQ_CPU}"
              memory: "${BENCH_SCHED_REQ_MEM}"
            limits:
              cpu: "${BENCH_SCHED_LIM_CPU}"
              memory: "${BENCH_SCHED_LIM_MEM}"
          volumeMounts:
            - mountPath: /config
              name: scheduler-config
      volumes:
        - name: scheduler-config
          configMap:
            name: eno-scheduler-config
            items:
              - key: eno-scheduler-config
                path: scheduler.config
YAML
}

{
  for i in $(seq 0 $((COUNT - 1))); do
    echo "---"
    generate_scheduler_yaml "$i"
  done
} | kubectl apply -f -

# ── Step 4: 等待所有实例就绪 ──
for i in $(seq 0 $((COUNT - 1))); do
  wait_deployment_ready "${ENO_NAMESPACE}" "scheduler-${i}" "${WAIT_READY_TIMEOUT}"
done

log_info "✓ ${COUNT} 个 Scheduler 实例已就绪"
echo ""
kubectl get deployment -n "${ENO_NAMESPACE}" --no-headers | grep "^scheduler"
