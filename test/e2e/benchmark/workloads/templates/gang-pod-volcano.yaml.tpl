apiVersion: scheduling.volcano.sh/v1beta1
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
    scheduling.volcano.sh/group-name: bench-gang-${GROUP_INDEX}
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
