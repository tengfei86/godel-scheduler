#!/usr/bin/env python3
"""fault-plot.py — 绘制 6.6 节故障注入实验的时序图

用法:
  python3 fault-plot.py <run_dir> [--out <dir>] [--format png|pdf]

<run_dir> 是 run-experiment.sh --inject ... 生成的目录，含
  * inject-manifest.json  注入元数据（含时间戳）
  * metadata.txt          实验起止时间
  * *.json                Prometheus 导出时序

输出:
  <run_dir>/plots/ 下的两张图（layer0 / layer3 各一张双轴时序图）以及
  <run_dir>/plots/summary.txt（分段计数 + 不变量 I 断言复述）
"""
import argparse, json, os, sys, math
from pathlib import Path

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    print("请先: pip install matplotlib", file=sys.stderr); sys.exit(1)

# 中文字体：macOS 优先 PingFang / Heiti; Linux 优先 Noto CJK; 都找不到就默认（会 warn 但仍出图）
for _f in ["PingFang SC", "Arial Unicode MS", "Heiti SC", "Songti SC",
           "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei"]:
    try:
        matplotlib.font_manager.findfont(_f, fallback_to_default=False)
        plt.rcParams["font.sans-serif"] = [_f]
        break
    except Exception:
        continue
plt.rcParams["axes.unicode_minus"] = False


def load_series(path):
    """读取 prometheus 导出 JSON，返回 list of (t_epoch, value_or_None)."""
    if not path.exists():
        return []
    with path.open() as f:
        obj = json.load(f)
    result = (obj.get("data") or {}).get("result") or []
    if not result:
        return []
    # 若是 by-pod 分组则聚合成 dict[pod] -> series
    series = {}
    for r in result:
        pod = (r.get("metric") or {}).get("pod", "__total__")
        vals = []
        for t, v in r.get("values", []):
            try:
                fv = float(v)
                if math.isnan(fv):
                    fv = None
            except (TypeError, ValueError):
                fv = None
            vals.append((int(t), fv))
        series[pod] = vals
    return series


def series_total(series):
    """当 series 是单条 (or __total__) 返回 [(t,v)]；多条则按时间点求和."""
    if not series:
        return []
    if len(series) == 1:
        return list(series.values())[0]
    # 汇总
    all_t = sorted({t for s in series.values() for t, _ in s})
    out = []
    for t in all_t:
        s = 0.0
        n = 0
        for k, vals in series.items():
            v = next((v for tt, v in vals if tt == t), None)
            if v is not None:
                s += v; n += 1
        out.append((t, s if n else None))
    return out


def rel_time(series, t0):
    return [((t - t0), v) for t, v in series if v is not None]


def load_manifest(run_dir):
    p = run_dir / "inject-manifest.json"
    if not p.exists():
        raise SystemExit(f"缺少 {p}")
    with p.open() as f:
        return json.load(f)


def load_metadata(run_dir):
    p = run_dir / "metadata.txt"
    meta = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1); meta[k.strip()] = v.strip()
    return meta


def plot_layer0(run_dir, out_dir, fmt):
    m = load_manifest(run_dir)
    meta = load_metadata(run_dir)
    t0 = int(meta.get("start_time", m["inject_start_ts"] - 30))
    inject_rel = m["inject_start_ts"] - t0

    nvf = series_total(load_series(run_dir / "node_validation_failures.json"))
    dfb = series_total(load_series(run_dir / "dispatcher_fallback.json"))
    suc = series_total(load_series(run_dir / "bind_success_rate.json"))

    fig, ax1 = plt.subplots(figsize=(10, 4.2))
    ax2 = ax1.twinx()

    xs, ys = zip(*rel_time(nvf, t0)) if any(v for _, v in nvf) else ([], [])
    ax1.plot(xs, ys, color="#d62728", label="node_validation_failures (rate1m)", linewidth=2)

    xs, ys = zip(*rel_time(dfb, t0)) if any(v for _, v in dfb) else ([], [])
    ax1.plot(xs, ys, color="#ff7f0e", label="dispatcher_fallback (rate1m)", linewidth=2, linestyle="--")

    xs, ys = zip(*rel_time(suc, t0)) if any(v for _, v in suc) else ([], [])
    ax2.plot(xs, ys, color="#2ca02c", label="bind_success_rate", linewidth=1.2, alpha=0.85)

    ax1.axvline(inject_rel, color="black", linestyle=":", label=f"inject @ T+{inject_rel}s")
    ax1.set_xlabel("time since load start (s)")
    ax1.set_ylabel("rate (events/s)")
    ax2.set_ylabel("success rate")
    ax2.set_ylim(0, 1.05)
    fig.suptitle(f"Layer 0 触发验证 (ENO, {meta.get('scale','?')}/{meta.get('workload','?')}, run {meta.get('run_id','?')})")

    lines, labels = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines + lines2, labels + labels2, loc="upper right", fontsize=8)
    ax1.grid(True, alpha=0.3)
    fig.tight_layout()

    out = out_dir / f"layer0-timeseries.{fmt}"
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print(f"  {out}")
    return out


def plot_layer3(run_dir, out_dir, fmt):
    m = load_manifest(run_dir)
    meta = load_metadata(run_dir)
    t0 = int(meta.get("start_time", m["inject_start_ts"] - 30))
    inject_rel = m["killed_ts"] - t0
    restored_rel = (m.get("restored_ts") or 0) - t0 if m.get("restored_ts") else None

    # Layer 3 的"回退阶跃"由 orphan_pods_reset_total 驱动（Reconciler 触发），
    # 而不是 Layer 0 里的 dispatcher_fallback_total（MaxLocalRetries）。
    orphan = series_total(load_series(run_dir / "orphan_pods_reset.json"))
    pending = series_total(load_series(run_dir / "pending_pods.json"))
    per_pod = load_series(run_dir / "bind_success_by_pod.json")

    fig, ax1 = plt.subplots(figsize=(10, 4.2))
    ax2 = ax1.twinx()

    xs, ys = zip(*rel_time(orphan, t0)) if any(v for _, v in orphan) else ([], [])
    ax1.plot(xs, ys, color="#ff7f0e", label="orphan_pods_reset (rate1m)", linewidth=2)

    xs, ys = zip(*rel_time(pending, t0)) if any(v for _, v in pending) else ([], [])
    ax2.plot(xs, ys, color="#1f77b4", label="pending_pods", linewidth=1.5, alpha=0.85)

    # 分实例的绑定速率
    colors = ["#2ca02c", "#9467bd", "#8c564b", "#e377c2"]
    for i, (pod, vals) in enumerate(sorted(per_pod.items())):
        xs, ys = zip(*rel_time(vals, t0)) if any(v for _, v in vals) else ([], [])
        ax1.plot(xs, ys, color=colors[i % len(colors)], linewidth=1, alpha=0.8,
                 label=f"bind rate: {pod}")

    ax1.axvline(inject_rel, color="black", linestyle=":", label=f"kill @ T+{inject_rel}s")
    if restored_rel is not None:
        ax1.axvline(restored_rel, color="gray", linestyle="--", label=f"restored @ T+{restored_rel}s")

    ax1.set_xlabel("time since load start (s)")
    ax1.set_ylabel("rate (pods/s)")
    ax2.set_ylabel("pending pods")
    fig.suptitle(f"Layer 3 触发验证 (ENO, {meta.get('scale','?')}/{meta.get('workload','?')}, run {meta.get('run_id','?')})")

    lines, labels = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines + lines2, labels + labels2, loc="upper right", fontsize=8)
    ax1.grid(True, alpha=0.3)
    fig.tight_layout()

    out = out_dir / f"layer3-timeseries.{fmt}"
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print(f"  {out}")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--out", default=None)
    ap.add_argument("--format", default="png", choices=["png", "pdf", "svg"])
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        raise SystemExit(f"目录不存在: {run_dir}")

    manifest = load_manifest(run_dir)
    out_dir = Path(args.out) if args.out else (run_dir / "plots")
    out_dir.mkdir(parents=True, exist_ok=True)

    layer = manifest.get("layer")
    if layer == "layer0":
        plot_layer0(run_dir, out_dir, args.format)
    elif layer == "layer3":
        plot_layer3(run_dir, out_dir, args.format)
    else:
        raise SystemExit(f"未知 layer: {layer!r}")


if __name__ == "__main__":
    main()
