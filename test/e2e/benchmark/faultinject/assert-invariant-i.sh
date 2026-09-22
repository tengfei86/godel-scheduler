#!/usr/bin/env bash
# assert-invariant-i.sh — 遍历命名空间下所有 Pod，断言
#   (1) spec.nodeName 非空 (bound)
#   (2) 同一 Pod 不重复出现
# 满足则 exit 0 并打印统计；违反则 exit 1。
#
# 用法: assert-invariant-i.sh <namespace>

set -eu
NS="${1:?用法: assert-invariant-i.sh <namespace>}"

# 注意：Python heredoc 用 python3 - 会占用 stdin，因此把 kubectl JSON
# 先写到临时文件，再用 arg 传给脚本读取。
JSON=$(mktemp)
trap 'rm -f "$JSON"' EXIT
kubectl get pods -n "$NS" -o json > "$JSON"

python3 - "$NS" "$JSON" <<'PY'
import json, sys, collections
ns, path = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
total, bound, unbound, dup, empty_name = 0, 0, 0, 0, 0
seen = collections.Counter()
unbound_names, dup_names = [], []
for item in data.get("items", []):
    total += 1
    name = item.get("metadata", {}).get("name", "")
    node = item.get("spec", {}).get("nodeName", "")
    if not name:
        empty_name += 1; continue
    seen[name] += 1
    if seen[name] > 1:
        dup += 1; dup_names.append(name)
    if node:
        bound += 1
    else:
        unbound += 1; unbound_names.append(name)

print(f"namespace={ns} total={total} bound={bound} unbound={unbound} dup={dup} empty_name={empty_name}")
if unbound_names:
    print("UNBOUND SAMPLE:", ", ".join(unbound_names[:20]))
if dup_names:
    print("DUPLICATE:", ", ".join(dup_names[:20]))

if unbound > 0 or dup > 0 or empty_name > 0:
    sys.exit(1)
sys.exit(0)
PY
