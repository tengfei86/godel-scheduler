apiVersion: v1
kind: Pod
metadata:
  name: bench-pod-${INDEX}
  namespace: ${NAMESPACE}
  annotations:
    eno.io/pod-state: pending
    eno.io/pod-resource-type: guaranteed
    eno.io/pod-launcher: kubelet
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
