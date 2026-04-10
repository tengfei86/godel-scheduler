kubectl logs -l app=eno-scheduler -n eno-system --tail 100 | grep -E "divideNodesByRequireAffinity input nodeCircle|TopologyElem after sort"
