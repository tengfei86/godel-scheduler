#!/usr/bin/env python3
"""fault-summary.py — 汇总 6.6 故障注入实验的关键计数与不变量断言。

用法:
  python3 fault-summary.py <run_dir> [--baseline <compare_dir>]

<run_dir>       run-experiment.sh --inject ... 的输出目录
<compare_dir>   6.5 节 s3/w2/inst3 的无故障对照目录 (可选)

输出:
  <run_dir>/plots/summary.txt (以及 stdout 上打印)
  * 分段累计计数: T-30..T0 (baseline) / T0..T+30 (inject) / T+30..T+90 (recovery)
  * 不变量 I 断言复述: bound / unbound / duplicate
  * 分实例绑定量 (Layer3 场景): sum of successful binds per pod
  * 总完成时间对比 (若提供 --baseline)
"""
import argparse, json, sys, math, statistics
from pathlib import Path


def load_series(path):
    if not Path(path).exists():
        return {}
    with open(path) as f:
        obj = json.load(f)
    out = {}
    for r in (obj.get("data") or {}).get("result") or []:
        pod = (r.get("metric") or {}).get("pod", "__total__")
        vals = []
        for t, v in r.get("values", []):
            try:
                fv = float(v)
                if math.isnan(fv): fv = None
            except (TypeError, ValueError):
                fv = None
            vals.append((int(t), fv))
        out[pod] = vals
    return out


def integrate(vals, t_lo, t_hi):
    """近似梯形积分：∫ rate(t) dt over [t_lo, t_hi]. 单位: 事件数."""
    total = 0.0
    prev_t, prev_v = None, None
    for t, v in vals:
        if v is None: v = 0.0
        if not (t_lo <= t <= t_hi):
            prev_t, prev_v = t, v
            continue
        if prev_t is not None and prev_v is not None and prev_t >= t_lo:
            total += 0.5 * (v + prev_v) * (t - prev_t)
        prev_t, prev_v = t, v
    return total


def load_meta(run_dir):
    p = run_dir / "metadata.txt"
    m = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1); m[k.strip()] = v.strip()
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--baseline", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    with (run_dir / "inject-manifest.json").open() as f:
        manifest = json.load(f)
    meta = load_meta(run_dir)
    t0 = int(meta.get("start_time"))
    inj_ts = int(manifest.get("inject_start_ts", manifest.get("killed_ts", t0 + 30)))
    layer = manifest.get("layer")

    lines = []
    lines.append(f"# Fault-injection summary — layer={layer}, run_dir={run_dir}")
    lines.append(f"start_time={t0}  inject_ts={inj_ts}  duration={meta.get('duration','?')}s")

    # segs[name] = (pre, inject_30s, recovery_60s)
    segs = {}
    def seg_counts(name, series_path):
        s = load_series(run_dir / series_path)
        if not s:
            segs[name] = None
            return
        vals = list(s.values())[0] if len(s) == 1 else \
               [(t, sum((v or 0) for v in [next((v for tt, v in ss if tt == t), None)
                                            for ss in s.values()])) for t in
                sorted({t for ss in s.values() for t, _ in ss})]
        pre = integrate(vals, inj_ts - 30, inj_ts)
        during = integrate(vals, inj_ts, inj_ts + 30)
        recovery = integrate(vals, inj_ts + 30, inj_ts + 90)
        segs[name] = (pre, during, recovery)
        lines.append(f"{name:<40s}  pre={pre:.1f}  inject_30s={during:.1f}  recovery_60s={recovery:.1f}")

    seg_counts("node_validation_failures", "node_validation_failures.json")
    seg_counts("dispatcher_fallback",      "dispatcher_fallback.json")
    seg_counts("bind_retries",             "bind_retries.json")
    seg_counts("pending_pods (integ)",     "pending_pods.json")

    # ── 分实例绑定量 (layer3 主要用) ──
    per_pod = load_series(run_dir / "bind_success_by_pod.json")
    if per_pod:
        lines.append("")
        lines.append("Per-Scheduler bind rate over [inject, inject+90s] (integrated pods):")
        for pod, vals in sorted(per_pod.items()):
            total = integrate(vals, inj_ts, inj_ts + 90)
            lines.append(f"  {pod:<30s}  ~{total:.0f} pods")

    # ── 不变量 I ──
    inv = run_dir / "invariant-i.txt"
    lines.append("")
    if inv.exists():
        lines.append("Invariant I assertion:")
        for l in inv.read_text().splitlines():
            lines.append(f"  {l}")
    else:
        lines.append("Invariant I assertion: (missing)")

    # ── 与 baseline 对比 ──
    if args.baseline:
        bm = load_meta(Path(args.baseline))
        d_base = int(bm.get("duration", 0) or 0)
        d_run = int(meta.get("duration", 0) or 0)
        if d_base and d_run:
            delta = d_run - d_base
            pct = 100.0 * delta / d_base
            lines.append(f"\nDuration vs baseline: run={d_run}s  base={d_base}s  Δ={delta:+d}s ({pct:+.1f}%)")

    # ── 显式 PASS/FAIL 判定 ──
    lines.append("")
    lines.append("=" * 60)
    lines.append(f"容错验证 (layer={layer})")
    lines.append("=" * 60)

    inv_txt = (run_dir / "invariant-i.txt").read_text() if (run_dir / "invariant-i.txt").exists() else ""
    inv_ok = ("unbound=0" in inv_txt) and ("dup=0" in inv_txt) and ("empty_name=0" in inv_txt)

    def check(name, passed, note=""):
        mark = "✅ PASS" if passed else "❌ FAIL"
        lines.append(f"  {mark}  {name}{('  — ' + note) if note else ''}")
        return passed

    # 判据与 verify.py 保持同一套语义：
    # - Layer 0 拦截窗口用 [inject, inject+90s] (informer 传播 patch 约需 10~30s,
    #   峰值往往落在 [+30, +90], 30s 窗口会漏采)
    # - Layer 3 ② 用"被杀 pod 占同期总绑定量比例 < 5%"取代绝对阈值
    # - Layer 3 ④ 窗口跟着 restored_ts 走, 支持长 outage
    def load_flat(name):
        s = load_series(run_dir / name)
        if not s: return []
        if len(s) == 1: return list(s.values())[0]
        all_t = sorted({t for ss in s.values() for t, _ in ss})
        return [(t, sum((v or 0) for v in [next((v for tt, v in ss if tt == t), None)
                                            for ss in s.values()])) for t in all_t]

    all_ok = True
    if layer == "layer0":
        nvf_flat = load_flat("node_validation_failures.json")
        dfb_flat = load_flat("dispatcher_fallback.json")
        nvf_90 = integrate(nvf_flat, inj_ts, inj_ts + 90)
        dfb_90 = integrate(dfb_flat, inj_ts, inj_ts + 90)
        target = manifest.get("patched_count", 0)

        c1 = check("① NodeValidator 有拦截 (rate>0)",
                   nvf_90 > 0, f"inject_90s 积分={nvf_90:.1f}")
        c2 = check("② Dispatcher 回退与拦截同步",
                   dfb_90 > 0, f"inject_90s 积分={dfb_90:.1f}")
        c3 = check("③ 不变量 I (bound & unique)", inv_ok,
                   inv_txt.splitlines()[0] if inv_txt else "无断言")
        c4 = check("④ 拦截规模与 patched 节点相当",
                   nvf_90 >= max(5.0, target * 0.3),
                   f"拦截≈{nvf_90:.0f} vs patched={target}, 阈值={max(5,target*0.3):.0f}")
        all_ok = c1 and c2 and c3 and c4

    elif layer == "layer3":
        killed = manifest.get("target_pod", "")
        # restored_ts 决定 peak/recover 窗口边界（长 outage 场景）
        restored_ts = int(manifest.get("restored_ts") or 0)
        if restored_ts and restored_ts > inj_ts:
            peak_end = restored_ts + 15
            recover_start = restored_ts + 30
            recover_end = restored_ts + 90
            dfb_end = max(inj_ts + 90, peak_end)
        else:
            peak_end = inj_ts + 45
            recover_start = inj_ts + 45
            recover_end = inj_ts + 90
            dfb_end = inj_ts + 90

        # ① Dispatcher 回退阶跃：orphan_pods_reset_total 为主, 拦截+回退为辅
        orphan_flat = load_flat("orphan_pods_reset.json")
        dfb_flat = load_flat("dispatcher_fallback.json")
        orphan_90 = integrate(orphan_flat, inj_ts, dfb_end)
        dfb_90 = integrate(dfb_flat, inj_ts, dfb_end)
        c1 = check("① Dispatcher/Reconciler 回退阶跃",
                   orphan_90 > 0 or dfb_90 > 0,
                   f"orphan_reset={orphan_90:.1f} dispatcher_fallback={dfb_90:.1f}")

        # ② 被杀实例停止绑定 - 用比值判据
        per_pod = load_series(run_dir / "bind_success_by_pod.json")
        killed_binds_after = 0.0; others_binds_after = 0.0
        for pod, vals in per_pod.items():
            a = integrate(vals, inj_ts, inj_ts + 90)
            if pod == killed:
                killed_binds_after += a
            else:
                others_binds_after += a
        total_after = killed_binds_after + others_binds_after
        ratio = killed_binds_after / total_after if total_after > 0 else 0.0
        c2 = check("② 被杀实例停止绑定 (占同期总量 < 5%)",
                   killed_binds_after < 0.05 * max(1.0, total_after),
                   f"killed={killed_binds_after:.0f} others={others_binds_after:.0f} "
                   f"ratio={ratio:.2%}")

        # ③ 存活实例接管
        c3 = check("③ 存活实例接管",
                   others_binds_after > 0,
                   f"others_after={others_binds_after:.0f}")

        # ④ pending 尖峰后回落 - 窗口跟着 restored_ts 走
        pend_flat = load_flat("pending_pods.json")
        pend_pre_max = max((v or 0) for t, v in pend_flat
                            if inj_ts - 30 <= t < inj_ts and v is not None) if pend_flat else 0
        pend_peak = max((v or 0) for t, v in pend_flat
                         if inj_ts <= t < peak_end and v is not None) if pend_flat else 0
        recover_vals = [(v or 0) for t, v in pend_flat
                        if recover_start <= t < recover_end and v is not None]
        pend_recover_min = min(recover_vals) if recover_vals else float("inf")
        c4 = check("④ pending 尖峰后回落",
                   pend_peak > max(pend_pre_max + 5, pend_pre_max * 1.5) and
                   pend_recover_min <= pend_pre_max + 15,
                   f"pre_max={pend_pre_max:.0f} peak={pend_peak:.0f} "
                   f"recover_min={pend_recover_min:.0f} "
                   f"(recover_window=[+{recover_start-inj_ts}s, +{recover_end-inj_ts}s])")

        # ⑤ 不变量 I
        c5 = check("⑤ 不变量 I (bound & unique)", inv_ok,
                   inv_txt.splitlines()[0] if inv_txt else "无断言")
        all_ok = c1 and c2 and c3 and c4 and c5
    else:
        lines.append(f"  未知 layer={layer!r}")

    lines.append("")
    lines.append(f"总判定: {'✅ 容错机制验证通过' if all_ok else '❌ 至少一项未通过，请查看上表'}")

    text = "\n".join(lines)
    print(text)
    out_path = Path(args.out) if args.out else (run_dir / "plots" / "summary.txt")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text + "\n")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
