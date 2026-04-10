apiVersion: scheduling.godel.kubewharf.io/v1alpha1
kind: PodGroup
metadata:
  name: bench-gang-${GROUP_INDEX}
  namespace: ${NAMESPACE}
spec:
  minMember: ${GANG_SIZE}
---
apiVersion: v1
kind: Pod
metadata:
  name: bench-gang-${GROUP_INDEX}-${MEMBER_INDEX}
  namespace: ${NAMESPACE}
  annotations:
    godel.bytedance.com/pod-state: pending
    godel.bytedance.com/pod-resource-type: guaranteed
    godel.bytedance.com/pod-launcher: kubelet
    scheduling.godel.bytedance.com/pod-group-name: bench-gang-${GROUP_INDEX}
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
