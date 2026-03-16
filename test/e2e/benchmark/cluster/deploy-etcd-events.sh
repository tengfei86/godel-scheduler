#!/usr/bin/env bash
# deploy-etcd-events.sh — 在 kind 控制面节点内部署事件专用 etcd
#
# API Server 通过 --etcd-servers-overrides="/events#http://127.0.0.1:2479"
# 将 Event 对象写入独立 etcd，避免事件洪峰冲击主 etcd 的写入性能。
#
# 用法:
#   bash deploy-etcd-events.sh [kind-cluster-name]
#
# 前置条件:
#   - kind 集群已创建
#   - kind-config.yml 中已配置 etcd-servers-overrides

set -eu

CLUSTER_NAME="${1:-godel-bench}"
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"

echo "[INFO] 在 ${CONTROL_PLANE} 中部署事件专用 etcd..."

# 获取主 etcd 的镜像版本（保持一致）
ETCD_IMAGE=$(docker exec "$CONTROL_PLANE" crictl images --output json 2>/dev/null \
  | python3 -c "
import sys, json
images = json.load(sys.stdin).get('images', [])
for img in images:
    for tag in img.get('repoTags', []):
        if 'etcd' in tag:
            print(tag)
            sys.exit(0)
print('registry.k8s.io/etcd:3.5.12-0')
" 2>/dev/null)

echo "[INFO] 使用 etcd 镜像: ${ETCD_IMAGE}"

# 写入 static pod manifest
docker exec "$CONTROL_PLANE" bash -c "cat > /etc/kubernetes/manifests/etcd-events.yaml" <<EOF
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
      image: ${ETCD_IMAGE}
      command:
        - etcd
        - --data-dir=/var/lib/etcd-events
        - --name=etcd-events
        - --listen-client-urls=http://0.0.0.0:2479
        - --advertise-client-urls=http://127.0.0.1:2479
        - --listen-peer-urls=http://0.0.0.0:2480
        # ── 性能调优 ──
        - --quota-backend-bytes=4294967296
        - --auto-compaction-mode=periodic
        - --auto-compaction-retention=1h
        - --snapshot-count=10000
        - --experimental-backend-batch-interval=10ms
        - --experimental-backend-batch-limit=1000
        - --max-request-bytes=10485760
      ports:
        - containerPort: 2479
          hostPort: 2479
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
EOF

echo "[INFO] 等待 etcd-events Pod 就绪..."
for i in $(seq 1 30); do
  if kubectl get pod -n kube-system etcd-events-"${CONTROL_PLANE}" --no-headers 2>/dev/null | grep -q Running; then
    echo "[INFO] ✓ etcd-events 已就绪"
    # 验证连通性
    docker exec "$CONTROL_PLANE" etcdctl --endpoints=http://127.0.0.1:2479 endpoint health 2>/dev/null && {
      echo "[INFO] ✓ etcd-events 端点可达"
      exit 0
    }
  fi
  sleep 2
done

echo "[WARN] etcd-events 可能尚未完全就绪，请手动检查:"
echo "  kubectl get pod -n kube-system | grep etcd-events"
echo "  kubectl logs -n kube-system etcd-events-${CONTROL_PLANE}"
