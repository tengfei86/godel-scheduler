yer=layer0)
============================================================
  ❌ FAIL  ① NodeValidator 有拦截 (rate>0)  — inject_30s 积分=0.0
  ❌ FAIL  ② Dispatcher 回退与拦截同步  — inject_30s 积分=0.0
  ✅ PASS  ③ 不变量 I (bound & unique)  — namespace=bench total=50000 bound=50000 unbound=0 dup=0 empty_name=0
  ❌ FAIL  ④ 拦截规模与 patched 节点相当  — 拦截≈0 vs patched=100

总判定: ❌ 至少一项未通过，请查看上表
[ERROR] 16:39:28   ❌ 容错验证未通过 (见 /root/dev/godel-scheduler/test/e2e/benchmark/results/faultinject/layer0/a_s2_w2_inst3/run1/plots/verify.txt)
[STEP]  16:39:28 analyze /root/dev/godel-scheduler/test/e2e/benchmark/results/faultinject/layer3/a_s2_w2_inst3/run1/
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:179: UserWarning: Glyph 35302 (\N{CJK UNIFIED IDEOGRAPH-89E6}) missing from font(s) DejaVu Sans.
  fig.tight_layout()
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:179: UserWarning: Glyph 21457 (\N{CJK UNIFIED IDEOGRAPH-53D1}) missing from font(s) DejaVu Sans.
  fig.tight_layout()
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:179: UserWarning: Glyph 39564 (\N{CJK UNIFIED IDEOGRAPH-9A8C}) missing from font(s) DejaVu Sans.
  fig.tight_layout()
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:179: UserWarning: Glyph 35777 (\N{CJK UNIFIED IDEOGRAPH-8BC1}) missing from font(s) DejaVu Sans.
  fig.tight_layout()
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:182: UserWarning: Glyph 35302 (\N{CJK UNIFIED IDEOGRAPH-89E6}) missing from font(s) DejaVu Sans.
  fig.savefig(out, dpi=150)
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:182: UserWarning: Glyph 21457 (\N{CJK UNIFIED IDEOGRAPH-53D1}) missing from font(s) DejaVu Sans.
  fig.savefig(out, dpi=150)
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:182: UserWarning: Glyph 39564 (\N{CJK UNIFIED IDEOGRAPH-9A8C}) missing from font(s) DejaVu Sans.
  fig.savefig(out, dpi=150)
/root/dev/godel-scheduler/test/e2e/benchmark/faultinject/fault-plot.py:182: UserWarning: Glyph 35777 (\N{CJK UNIFIED IDEOGRAPH-8BC1}) missing from font(s) DejaVu Sans.
  fig.savefig(out, dpi=150)
  /root/dev/godel-scheduler/test/e2e/benchmark/results/faultinject/layer3/a_s2_w2_inst3/run1/plots/layer3-timeseries.png
# Fault-injection summary — layer=layer3, run_dir=/root/dev/godel-scheduler/test/e2e/benchmark/results/faultinject/layer3/a_s2_w2_inst3/run1
start_time=1790151753  inject_ts=1790151769  duration=788s
node_validation_failures                  pre=0.0  inject_30s=36.7  recovery_60s=292.0
dispatcher_fallback                       pre=0.0  inject_30s=36.7  recovery_60s=292.0
pending_pods (integ)                      pre=45.0  inject_30s=210.0  recovery_60s=1852.5

Per-Scheduler bind rate over [inject, inject+90s] (integrated pods):
  scheduler-0-759b9fbb9f-7rsss    ~189 pods
  scheduler-0-759b9fbb9f-8j49p    ~0 pods
  scheduler-1-cdc6cbdf8-llqmq     ~7218 pods
  scheduler-2-ff8689dbf-gbmf6     ~3569 pods

Invariant I assertion:
  namespace=bench total=50000 bound=50000 unbound=0 dup=0 empty_name=0

Duration vs baseline: run=788s  base=680s  Δ=+108s (+15.9%)

============================================================
容错验证 (layer=layer3)
============================================================
  ✅ PASS  ① Dispatcher 回退阶跃  — inject_30s 积分=36.7
  ❌ FAIL  ② 被杀实例停止绑定  — before=0 after=189
  ✅ PASS  ③ 存活实例接管  — before=17 after=10787
  ❌ FAIL  ④ pending 尖峰后回落  — pre=45 peak=210 recover=1852
  ✅ PASS  ⑤ 不变量 I (bound & unique)  — namespace=bench total=50000 bound=50000 unbound=0 dup=0 empty_name=0

