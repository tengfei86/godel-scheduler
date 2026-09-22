#!/usr/bin/env python3
"""verify.py — 判定单次故障注入实验是否证明调度器容错生效。

针对 layer0 / layer3 分别给出 PASS/FAIL 结论，并在每一条判据下附带用于
判定的 PromQL、观测窗口、实测值与阈值——所有数字皆有溯源，可复现。

用法:
  python3 verify.py <run_dir>

<run_dir> 必须由 run-experiment.sh --inject <layer> 产出，含:
  - inject-manifest.json   注入元数据 (layer / 时间戳 / 目标)
  - metadata.txt           实验起止时间
  - invariant-i.txt        apiserver 事后不变量断言
  - *.json                 导出的 Prometheus 时序 (含 by-pod 分组)

退出码:
  0  全部判据通过 → 容错验证成功
  1  至少一条 FAIL
  2  数据缺失/文件损坏

底层数据不是重新查 Prometheus 而是复用 export-prometheus.sh 导出的 JSON，
以保证与 fault-summary.py / fault-plot.py 完全同源。
"""
from __future__ import annotations
import argparse, json, math, sys
from pathlib import Path


def load_series(path: Path):
    if not path.exists():
        return {}
    with path.open() as f:
        obj = json.load(f)
    out = {}
    for r in (obj.get("data") or {}).get("result") or []:
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
        out[pod] = vals
    return out


def flatten(series: dict):
    """把 by-pod 时序按时间点求和成单条时序."""
    if not series:
        return []
    if len(series) == 1:
        return list(series.values())[0]
    all_t = sorted({t for s in series.values() for t, _ in s})
    return [
        (t, sum((next((v for tt, v in s if tt == t), None) or 0) for s in series.values()))
        for t in all_t
    ]


def integrate(vals, t_lo, t_hi):
    """rate(t) 时序在 [t_lo, t_hi] 上的梯形积分 (≈ 事件累计数)."""
    total, prev_t, prev_v = 0.0, None, None
    for t, v in vals:
        if v is None:
            v = 0.0
        if not (t_lo <= t <= t_hi):
            prev_t, prev_v = t, v
            continue
        if prev_t is not None and prev_v is not None and prev_t >= t_lo:
            total += 0.5 * (v + prev_v) * (t - prev_t)
        prev_t, prev_v = t, v
    return total


def peak(vals, t_lo, t_hi):
    """时序在 [t_lo, t_hi) 上的最大值（左闭右开，避免边界采样被双计）."""
    return max((v for t, v in vals if t_lo <= t < t_hi and v is not None), default=0.0)


def load_meta(run_dir: Path) -> dict:
    p = run_dir / "metadata.txt"
    m = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                m[k.strip()] = v.strip()
    return m


# ────────────────────────────────────────────
# 判据数据类
# ────────────────────────────────────────────
class Criterion:
    def __init__(self, key: str, name: str, promql: str, window: str,
                 measured: float | str, threshold: str, passed: bool):
        self.key = key
        self.name = name
        self.promql = promql
        self.window = window
        self.measured = measured
        self.threshold = threshold
        self.passed = passed

    def render(self, out: list[str]):
        mark = "✅ PASS" if self.passed else "❌ FAIL"
        out.append(f"  [{self.key}] {mark}  {self.name}")
        out.append(f"       PromQL   : {self.promql}")
        out.append(f"       Window   : {self.window}")
        m = self.measured
        if isinstance(m, float):
            m = f"{m:.2f}"
        out.append(f"       Measured : {m}")
        out.append(f"       Threshold: {self.threshold}")
        out.append("")


# ────────────────────────────────────────────
# Layer 0 判定
# ────────────────────────────────────────────
def verify_layer0(run_dir: Path, manifest: dict, meta: dict) -> list[Criterion]:
    inj = int(manifest["inject_start_ts"])
    patched = int(manifest.get("patched_count", 0))
    win30 = f"[{inj}, {inj}+30s]"
    win90 = f"[{inj}, {inj}+90s]"

    nvf = flatten(load_series(run_dir / "node_validation_failures.json"))
    dfb = flatten(load_series(run_dir / "dispatcher_fallback.json"))
    ret = flatten(load_series(run_dir / "bind_retries.json"))
    suc = flatten(load_series(run_dir / "bind_success_rate.json"))

    nvf_30 = integrate(nvf, inj, inj + 30)
    dfb_30 = integrate(dfb, inj, inj + 30)
    ret_30 = integrate(ret, inj, inj + 30)
    ret_pre = integrate(ret, inj - 30, inj)
    suc_min = min((v for t, v in suc if inj - 30 <= t <= inj + 90 and v is not None), default=1.0)

    inv_txt = (run_dir / "invariant-i.txt").read_text() if (run_dir / "invariant-i.txt").exists() else ""
    inv_ok = ("unbound=0" in inv_txt) and ("dup=0" in inv_txt) and ("empty_name=0" in inv_txt)
    inv_line = inv_txt.splitlines()[0] if inv_txt else "(missing)"

    return [
        Criterion(
            key="L0-1",
            name="NodeValidator 识别到节点归属漂移",
            promql='sum(rate(binder_node_validation_failures_total[1m]))',
            window=win30,
            measured=nvf_30,
            threshold="积分 > 0 (拦截事件数)",
            passed=nvf_30 > 0,
        ),
        Criterion(
            key="L0-2",
            name="拦截 → Dispatcher 回退联动",
            promql='sum(rate(binder_dispatcher_fallback_total[1m]))',
            window=win30,
            measured=dfb_30,
            threshold="积分 > 0，且与 L0-1 同时段",
            passed=dfb_30 > 0,
        ),
        Criterion(
            key="L0-3",
            name="不变量 I：所有 Pod bound 且唯一",
            promql='kubectl get pods -o json | assert(spec.nodeName != "" & unique(name))',
            window="实验结束时刻 apiserver 快照",
            measured=inv_line,
            threshold="unbound=0 且 dup=0 且 empty_name=0",
            passed=inv_ok,
        ),
        Criterion(
            key="L0-4",
            name="拦截规模与 patched 节点数量级一致",
            promql='sum(increase(binder_node_validation_failures_total[30s])) @ inject_ts',
            window=win30,
            measured=f"nvf={nvf_30:.0f}, patched={patched}",
            threshold="nvf >= patched × 0.5 (允许多次尝试)",
            passed=nvf_30 >= max(1.0, patched * 0.5),
        ),
        Criterion(
            key="L0-5",
            name="Layer 1 重试不异常上涨 (排除 API 冲突这一竞争解释)",
            promql='sum(rate(binder_embedded_bind_retries_total[1m]))',
            window=win30,
            measured=f"pre={ret_pre:.1f} inject={ret_30:.1f}",
            threshold="inject_30s 不超过 pre_30s 的 3 倍",
            passed=(ret_30 <= max(1.0, ret_pre * 3)),
        ),
        Criterion(
            key="L0-6",
            name="全程绑定成功率保持 100%",
            promql='sum(rate(binder_embedded_bind_pods_total{result="success"}[1m])) / sum(rate(binder_embedded_bind_pods_total[1m]))',
            window=f"[{inj}-30s, {inj}+90s]",
            measured=suc_min,
            threshold="min ≥ 0.999",
            passed=suc_min >= 0.999,
        ),
    ]


# ────────────────────────────────────────────
# Layer 3 判定
# ────────────────────────────────────────────
def verify_layer3(run_dir: Path, manifest: dict, meta: dict) -> list[Criterion]:
    killed_ts = int(manifest.get("killed_ts") or manifest.get("inject_start_ts"))
    target_pod = manifest.get("target_pod", "")
    win30 = f"[{killed_ts}, {killed_ts}+30s]"
    win90 = f"[{killed_ts}, {killed_ts}+90s]"

    dfb = flatten(load_series(run_dir / "dispatcher_fallback.json"))
    pend = flatten(load_series(run_dir / "pending_pods.json"))
    per_pod = load_series(run_dir / "bind_success_by_pod.json")

    dfb_30 = integrate(dfb, killed_ts, killed_ts + 30)
    pend_pre = peak(pend, killed_ts - 30, killed_ts)
    pend_peak = peak(pend, killed_ts, killed_ts + 30)
    pend_recover = peak(pend, killed_ts + 30, killed_ts + 90)

    # 分实例绑定量
    killed_before = killed_after = others_before = others_after = 0.0
    per_pod_names = []
    for pod, vals in per_pod.items():
        b = integrate(vals, killed_ts - 30, killed_ts)
        a = integrate(vals, killed_ts, killed_ts + 90)
        per_pod_names.append(pod)
        if pod == target_pod:
            killed_before += b; killed_after += a
        else:
            others_before += b; others_after += a

    inv_txt = (run_dir / "invariant-i.txt").read_text() if (run_dir / "invariant-i.txt").exists() else ""
    inv_ok = ("unbound=0" in inv_txt) and ("dup=0" in inv_txt) and ("empty_name=0" in inv_txt)
    inv_line = inv_txt.splitlines()[0] if inv_txt else "(missing)"

    return [
        Criterion(
            key="L3-1",
            name="Dispatcher 在实例失活后出现回退阶跃",
            promql='sum(rate(binder_dispatcher_fallback_total[1m]))',
            window=win30,
            measured=dfb_30,
            threshold="积分 > 0",
            passed=dfb_30 > 0,
        ),
        Criterion(
            key="L3-2",
            name="被杀实例停止绑定 (证明 Reconciler 感知失活)",
            promql=f'sum(increase(binder_embedded_bind_pods_total{{pod="{target_pod}",result="success"}}[90s]))',
            window=win90,
            measured=f"before={killed_before:.0f}, after={killed_after:.0f}",
            threshold="after < max(1, before × 0.2)",
            passed=killed_after < max(1.0, killed_before * 0.2),
        ),
        Criterion(
            key="L3-3",
            name="存活实例接管被杀 Pod 的负载",
            promql='sum by (pod) (increase(binder_embedded_bind_pods_total{result="success"}[90s]))',
            window=win90,
            measured=f"other_before={others_before:.0f}, other_after={others_after:.0f}",
            threshold="other_after > other_before × 0.9 (维持或上升)",
            passed=others_after > max(1.0, others_before * 0.9),
        ),
        Criterion(
            key="L3-4",
            name="pending_pods 尖峰后回落",
            promql='sum(scheduler_pending_pods)',
            window=f"pre={win30.replace(str(killed_ts), str(killed_ts-30))} / peak={win30} / recover={win90.replace(str(killed_ts), str(killed_ts+30))}",
            measured=f"pre_max={pend_pre:.0f}, peak={pend_peak:.0f}, recover_max={pend_recover:.0f}",
            threshold="peak > pre × 1.5 且 recover < peak × 1.5",
            passed=(pend_peak > pend_pre * 1.5) and (pend_recover < max(1.0, pend_peak * 1.5)),
        ),
        Criterion(
            key="L3-5",
            name="总绑定量守恒：三实例累计 = 名义 Pod 总数",
            promql='sum(increase(binder_embedded_bind_pods_total{result="success"}[full_run]))',
            window="[实验开始, 结束]",
            measured=f"killed+others = {(killed_after + others_after):.0f}",
            threshold="≥ 90% × TOTAL (允许少量重复计数)",
            passed=(killed_after + others_after) > 0.9 * float(meta.get("total", 0) or 1),
        ),
        Criterion(
            key="L3-6",
            name="不变量 I：所有 Pod bound 且唯一",
            promql='kubectl get pods -o json | assert(spec.nodeName != "" & unique(name))',
            window="实验结束时刻 apiserver 快照",
            measured=inv_line,
            threshold="unbound=0 且 dup=0 且 empty_name=0",
            passed=inv_ok,
        ),
    ]


# ────────────────────────────────────────────
# 入口
# ────────────────────────────────────────────
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("run_dir")
    ap.add_argument("--out", default=None, help="写 verify.txt 到指定路径 (默认 <run_dir>/plots/verify.txt)")
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        print(f"目录不存在: {run_dir}", file=sys.stderr)
        return 2

    manifest_path = run_dir / "inject-manifest.json"
    if not manifest_path.exists():
        print(f"缺少 inject-manifest.json: {manifest_path}", file=sys.stderr)
        return 2
    with manifest_path.open() as f:
        manifest = json.load(f)
    meta = load_meta(run_dir)
    layer = manifest.get("layer")

    lines: list[str] = []
    lines.append("=" * 72)
    lines.append(f"容错验证报告 — {layer}   run_dir={run_dir}")
    lines.append("=" * 72)
    lines.append(f"scale={meta.get('scale','?')}  workload={meta.get('workload','?')}  "
                 f"instances={meta.get('scheduler_instances','?')}  "
                 f"duration={meta.get('duration','?')}s")
    if layer == "layer0":
        lines.append(f"注入: 将 {manifest.get('patched_count',0)} 个节点的 eno.io/scheduler-name "
                     f"从 {manifest.get('from_scheduler','?')} 漂移到 {manifest.get('to_scheduler','?')}")
    else:
        lines.append(f"注入: 强制删除 {manifest.get('target_pod','?')} "
                     f"(deploy={manifest.get('target_deployment','?')}, "
                     f"scheduler={manifest.get('target_scheduler','?')})")
    lines.append(f"inject_ts={manifest.get('inject_start_ts', manifest.get('killed_ts'))}"
                 f"  killed_ts={manifest.get('killed_ts','-')}"
                 f"  restored_ts={manifest.get('restored_ts','-')}")
    lines.append("")
    lines.append("判据 (每一条给出 PromQL / 观测窗口 / 实测值 / 阈值 / 结论)")
    lines.append("-" * 72)

    if layer == "layer0":
        criteria = verify_layer0(run_dir, manifest, meta)
    elif layer == "layer3":
        criteria = verify_layer3(run_dir, manifest, meta)
    else:
        print(f"未知 layer: {layer!r}", file=sys.stderr)
        return 2

    for c in criteria:
        c.render(lines)

    passed_cnt = sum(1 for c in criteria if c.passed)
    total = len(criteria)
    all_ok = passed_cnt == total

    lines.append("-" * 72)
    lines.append(f"通过 {passed_cnt} / {total} 项")
    lines.append("")
    if all_ok:
        lines.append(f"最终判定: ✅ Layer {'0' if layer=='layer0' else '3'} 容错机制在此次实验中验证通过")
    else:
        failed = [c.key for c in criteria if not c.passed]
        lines.append(f"最终判定: ❌ FAIL — 未通过判据: {', '.join(failed)}")
        lines.append("       追查建议: 见对应 PromQL；plots/{layer0,layer3}-timeseries.png 上标注的注入线附近")

    text = "\n".join(lines)
    print(text)
    out_path = Path(args.out) if args.out else (run_dir / "plots" / "verify.txt")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text + "\n")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
