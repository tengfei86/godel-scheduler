apiVersion: v1
kind: Pod
metadata:
  name: bench-pod-${INDEX}
  namespace: ${NAMESPACE}
  annotations:
    godel.bytedance.com/pod-state: pending
    godel.bytedance.com/pod-resource-type: guaranteed
    godel.bytedance.com/pod-launcher: kubelet
spec:
  schedulerName: ${SCHEDULER_NAME}
  terminationGracePeriodSeconds: 0
  containers:
    - name: app
      image: ${PAUSE_IMAGE}
      resources:
        requests:
          cpu: "${CPU}m"
          memory: "${MEM}Mi"
        limits:
          cpu: "${CPU}m"
          memory: "${MEM}Mi"
