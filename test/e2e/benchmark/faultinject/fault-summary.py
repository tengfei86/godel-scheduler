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

    all_ok = True
    if layer == "layer0":
        nvf = segs.get("node_validation_failures")
        dfb = segs.get("dispatcher_fallback")
        target = manifest.get("patched_count", 0)
        # ① 拦截计数上涨：inject_30s 段的积分 > 0
        c1 = check("① NodeValidator 有拦截 (rate>0)",
                   nvf is not None and nvf[1] > 0,
                   f"inject_30s 积分={nvf[1]:.1f}" if nvf else "无采样")
        # ② 回退与拦截同步
        c2 = check("② Dispatcher 回退与拦截同步",
                   dfb is not None and dfb[1] > 0,
                   f"inject_30s 积分={dfb[1]:.1f}" if dfb else "无采样")
        # ③ 不变量 I 成立
        c3 = check("③ 不变量 I (bound & unique)", inv_ok, inv_txt.splitlines()[0] if inv_txt else "无断言")
        # ④ 拦截数量 ≈ patched 节点数量级（不严格要求相等，因为一个节点可能多次尝试）
        c4 = check("④ 拦截规模与 patched 节点相当",
                   nvf is not None and nvf[1] >= target * 0.5,
                   f"拦截≈{nvf[1]:.0f} vs patched={target}" if nvf else "无采样")
        all_ok = c1 and c2 and c3 and c4

    elif layer == "layer3":
        dfb = segs.get("dispatcher_fallback")
        pend = segs.get("pending_pods (integ)")
        killed = manifest.get("target_pod", "")
        per_pod = load_series(run_dir / "bind_success_by_pod.json")

        c1 = check("① Dispatcher 回退阶跃",
                   dfb is not None and dfb[1] > 0,
                   f"inject_30s 积分={dfb[1]:.1f}" if dfb else "无采样")

        # ② 被杀实例在注入后停止绑定：inject 后 60s 的绑定量应远低于其正常水平
        # 用完整 pod 名精确匹配。被 delete 的 pod 名在 per_pod 中会一直保留其历史
        # 时间序列，重建后是一个 NEW pod 名；因此"被杀"仅指 manifest.target_pod。
        killed_binds_after = killed_binds_before = 0.0
        others_binds_after = others_binds_before = 0.0
        for pod, vals in per_pod.items():
            b = integrate(vals, inj_ts - 30, inj_ts)
            a = integrate(vals, inj_ts, inj_ts + 90)
            if pod == killed:
                killed_binds_after += a; killed_binds_before += b
            else:
                others_binds_after += a; others_binds_before += b
        c2 = check("② 被杀实例停止绑定",
                   killed_binds_after < max(1.0, killed_binds_before * 0.2),
                   f"before={killed_binds_before:.0f} after={killed_binds_after:.0f}")

        # ③ 存活实例绑定上升接管
        c3 = check("③ 存活实例接管",
                   others_binds_after > others_binds_before * 0.9,
                   f"before={others_binds_before:.0f} after={others_binds_after:.0f}")

        # ④ pending 尖峰后回落（inject_30s 明显 > pre，recovery 应 < inject）
        c4 = check("④ pending 尖峰后回落",
                   pend is not None and pend[1] > pend[0] * 1.5 and pend[2] < pend[1] * 1.5,
                   f"pre={pend[0]:.0f} peak={pend[1]:.0f} recover={pend[2]:.0f}" if pend else "无采样")

        # ⑤ 不变量 I
        c5 = check("⑤ 不变量 I (bound & unique)", inv_ok, inv_txt.splitlines()[0] if inv_txt else "无断言")
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
