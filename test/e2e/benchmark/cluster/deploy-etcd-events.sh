#!/usr/bin/env bash
# deploy-etcd-events.sh — 在 kind 控制面节点内部署事件专用 etcd
#
# 流程:
#   1. 在控制面节点部署 etcd-events static pod (port 2479)
#   2. 等待就绪
#   3. 修改 API Server manifest 添加 --etcd-servers-overrides
#   4. API Server 自动重启并开始将 events 写入独立 etcd
#
# 用法:
#   bash deploy-etcd-events.sh [kind-cluster-name]

set -eu

CLUSTER_NAME="${1:-godel-bench}"
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"

echo "[INFO] 在 ${CONTROL_PLANE} 中部署事件专用 etcd..."

# ── Step 1: 部署 etcd-events static pod ──
docker exec "$CONTROL_PLANE" bash -c "cat > /etc/kubernetes/manifests/etcd-events.yaml" <<'MANIFEST'
apiVersion: v1
kind: Pod
metadata:
  name: etcd-events
  namespace: kube-system
  labels:
    component: etcd-events
    tier: control-plane
spec:
  hostNetwork: true
  priorityClassName: system-node-critical
  containers:
    - name: etcd-events
      image: registry.k8s.io/etcd:3.5.12-0
      command:
        - etcd
        - --data-dir=/var/lib/etcd-events
        - --name=etcd-events
        - --listen-client-urls=http://0.0.0.0:2479
        - --advertise-client-urls=http://127.0.0.1:2479
        - --listen-peer-urls=http://0.0.0.0:2480
        - --quota-backend-bytes=4294967296
        - --auto-compaction-mode=periodic
        - --auto-compaction-retention=1h
        - --snapshot-count=10000
      ports:
        - containerPort: 2479
          name: client
      volumeMounts:
        - name: etcd-events-data
          mountPath: /var/lib/etcd-events
      livenessProbe:
        httpGet:
          host: 127.0.0.1
          path: /health
          port: 2479
          scheme: HTTP
        initialDelaySeconds: 10
        periodSeconds: 10
        failureThreshold: 8
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
  volumes:
    - name: etcd-events-data
      hostPath:
        path: /var/lib/etcd-events
        type: DirectoryOrCreate
MANIFEST

echo "[INFO] 等待 etcd-events 就绪..."
for i in $(seq 1 30); do
  if docker exec "$CONTROL_PLANE" curl -sf http://127.0.0.1:2479/health >/dev/null 2>&1; then
    echo "[INFO] ✓ etcd-events 健康检查通过"
    break
  fi
  echo "  等待中... (${i}/30)"
  sleep 2
done

# 最终确认
if ! docker exec "$CONTROL_PLANE" curl -sf http://127.0.0.1:2479/health >/dev/null 2>&1; then
  echo "[ERROR] etcd-events 启动失败，跳过 API Server 修改"
  echo "[ERROR] 检查日志: docker exec $CONTROL_PLANE crictl logs \$(docker exec $CONTROL_PLANE crictl ps -a --name etcd-events -q)"
  exit 1
fi

# ── Step 2: 修改 API Server manifest 添加 etcd-servers-overrides ──
echo "[INFO] 修改 API Server 配置，添加 etcd-servers-overrides..."

# 检查是否已经有这个参数
if docker exec "$CONTROL_PLANE" grep -q "etcd-servers-overrides" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null; then
  echo "[INFO] API Server 已包含 etcd-servers-overrides，跳过"
else
  # 在 --etcd-servers= 行后面插入 overrides 参数
  docker exec "$CONTROL_PLANE" sed -i \
    '/--etcd-servers=/a\    - --etcd-servers-overrides=/events#http://127.0.0.1:2479' \
    /etc/kubernetes/manifests/kube-apiserver.yaml

  echo "[INFO] 等待 API Server 重启..."
  # kubelet 检测到 manifest 变更会自动重启 API Server
  sleep 5
  for i in $(seq 1 30); do
    if docker exec "$CONTROL_PLANE" curl -sf -k https://127.0.0.1:6443/healthz >/dev/null 2>&1; then
      echo "[INFO] ✓ API Server 重启完成"
      break
    fi
    echo "  等待 API Server... (${i}/30)"
    sleep 3
  done
fi

echo "[INFO] ✓ 事件 etcd 部署完成"
echo "[INFO]   主 etcd:   https://127.0.0.1:2379  (pods, nodes, ...)"
echo "[INFO]   事件 etcd: http://127.0.0.1:2479   (events)"
