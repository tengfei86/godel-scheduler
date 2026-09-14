#!/usr/bin/env python3
"""latency-compare.py — 从 run 聚合结果中提取 a(ENO) vs b(Gödel) 的延迟对比

用途：复现论文第 6 章表 6-5（调度延迟 P90/P99）与表 6-6（Pod E2E 延迟 P99）。

数据来源（按优先级）：
  1. results/{a,b}/{s}/{w}/inst{N}/avg/<metric>.json
     = gen-averages.sh --median 调 plot-results.py 生成的 3 次 run 聚合序列
       （逐时间点 nanmedian，时间轴步长 15 s，t=0 为该 run 导出序列的首个采样点）
  2. 时序点数不足时回退到 results/{a,b}/{s}/{w}/inst{N}/run{1,2,3}/run_<metric>.json
     = export-prometheus.sh 的 export_run_totals 导出的 run 级标量
       （用 run 首尾两次累计计数之差做 histogram_quantile，每 run 一个值，
        再对 3 条 run 取中位数；见该函数注释）

统计口径（与论文 §6.2 warmup/cooldown 约定一致）：
  1. 取聚合序列中的非 NaN 采样点；
  2. 剔除首部 trim_head 个采样点、尾部 trim_tail 个采样点
     （默认各 2 个 × 15 s = 负载前 30 s warmup 与结束前 30 s cooldown）；
  3. 对剩余采样点取中位数，作为该组在该场景的延迟取值；
  4. 改善率 = (Gödel - ENO) / Gödel，正值表示 ENO 更低。

场景集合以 results/compare/ 下的目录名为准（论文的权威场景清单）：
  {规模}_{负载}          → inst1
  {规模}_{负载}_inst3    → inst3

关于 n/a：
  - 剔除后剩余采样点少于 1 且无 run 级数据时输出 n/a。s1/w1 的调度延迟导出
    序列只有 4~5 个采样点，其中 a 侧剔除后为空；
  - w6（Gang）单次 run 仅 29~39 s，而时序分位基于 1 m rate 窗口，导出序列
    通常只有 0~1 个采样点。该场景需依赖 run 级回退（口径列显示 run），
    否则为 n/a。旧批次数据（2026-09 之前）没有 run_ 文件，回退不生效。

用法：
  ./latency-compare.py                    # 全部场景，markdown 表格
  ./latency-compare.py --trim-head 0 --trim-tail 0   # 不剔除（原始口径）
  ./latency-compare.py --scenario s3_w5_inst3 --detail
  ./latency-compare.py --no-run-total     # 禁用 run 级回退
  ./latency-compare.py --json out.json
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from pathlib import Path

RESULTS_DIR = Path(__file__).resolve().parent.parent / "results"
COMPARE_DIR = RESULTS_DIR / "compare"

# 论文表 6-5 / 表 6-6 使用的三个指标
DEFAULT_METRICS = [
    "scheduling_latency_p90",
    "scheduling_latency_p99",
    "pod_e2e_latency_p99",
]

GROUPS = ("a", "b")
GROUP_LABEL = {"a": "ENO", "b": "Gödel"}


def scenario_path(name: str) -> str:
    """compare 目录名 → results 相对路径 {s}/{w}/inst{N}"""
    scale, rest = name.split("_", 1)
    if rest.endswith("_inst3"):
        return f"{scale}/{rest[: -len('_inst3')]}/inst3"
    return f"{scale}/{rest}/inst1"


def load_values(path: Path) -> list[float]:
    """读取 prometheus json，返回单个 series 的数值序列（按时间顺序，含 NaN 剔除）"""
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return []
    result = payload.get("data", {}).get("result", [])
    if not result:
        return []
    out: list[float] = []
    for _, raw in result[0].get("values", []):
        try:
            value = float(raw)
        except (TypeError, ValueError):
            continue
        if value == value:  # 过滤 NaN
            out.append(value)
    return out


def trimmed_median(values: list[float], trim_head: int, trim_tail: int) -> float | None:
    if trim_tail:
        body = values[trim_head:-trim_tail]
    else:
        body = values[trim_head:]
    if not body:
        return None
    return statistics.median(body)


def collect(
    scenario: str,
    metric: str,
    trim_head: int,
    trim_tail: int,
    allow_run_total: bool = True,
) -> dict:
    sub = scenario_path(scenario)
    rec: dict = {"scenario": scenario, "path": sub, "metric": metric}
    for group in GROUPS:
        series = load_values(RESULTS_DIR / group / sub / "avg" / f"{metric}.json")
        rec[f"{group}_n"] = len(series)
        rec[f"{group}_value"] = trimmed_median(series, trim_head, trim_tail)
        rec[f"{group}_caliber"] = "series"
        # 逐 run 口径（不剔除首尾则为"整段中位数"），仅供查看离散度
        per_run = []
        for idx in (1, 2, 3):
            run_series = load_values(
                RESULTS_DIR / group / sub / f"run{idx}" / f"{metric}.json"
            )
            per_run.append(trimmed_median(run_series, 0, 0))
        rec[f"{group}_per_run"] = per_run

        # 时序点数不足（短 run，例如 w6 的 29~39 s）时回退到 run 级累计直方图分位：
        # export-prometheus.sh 导出的 run_<metric>.json 每条 run 给出一个标量，
        # 对存在的 run 取中位数。该路径不依赖 avg/ 目录是否存在。
        if rec[f"{group}_value"] is None and allow_run_total:
            run_totals = []
            for idx in (1, 2, 3):
                points = load_values(
                    RESULTS_DIR / group / sub / f"run{idx}" / f"run_{metric}.json"
                )
                if points:
                    run_totals.append(statistics.median(points))
            if run_totals:
                rec[f"{group}_value"] = statistics.median(run_totals)
                rec[f"{group}_caliber"] = "run-total"
                rec[f"{group}_n"] = len(run_totals)
    return rec


def fmt(value: float | None, width: int = 9, digits: int = 3) -> str:
    if value is None:
        return f"{'n/a':>{width}}"
    return f"{value:>{width}.{digits}f}"


def fmt_improve(a: float | None, b: float | None) -> str:
    if a is None or b is None or b == 0:
        return f"{'n/a':>9}"
    return f"{(b - a) / b * 100:>+8.1f}%"


def main() -> int:
    parser = argparse.ArgumentParser(description="a vs b 延迟对比提取器")
    parser.add_argument("--trim-head", type=int, default=2, help="剔除序列首部采样点数（默认 2）")
    parser.add_argument("--trim-tail", type=int, default=2, help="剔除序列尾部采样点数（默认 2）")
    parser.add_argument("--scenario", action="append", help="只处理指定场景，可重复")
    parser.add_argument("--metric", action="append", help="只处理指定指标，可重复")
    parser.add_argument("--detail", action="store_true", help="附加逐 run 数值与采样点数")
    parser.add_argument(
        "--no-run-total",
        action="store_true",
        help="禁用 run 级累计直方图分位回退（只看时序口径）",
    )
    parser.add_argument("--json", metavar="PATH", help="同时写出 JSON")
    args = parser.parse_args()

    if not COMPARE_DIR.is_dir():
        print(f"错误: 找不到场景目录 {COMPARE_DIR}", file=sys.stderr)
        return 1

    scenarios = sorted(
        d.name for d in COMPARE_DIR.iterdir() if d.is_dir() and not d.name.startswith(".")
    )
    if args.scenario:
        missing = [s for s in args.scenario if s not in scenarios]
        if missing:
            print(f"错误: 以下场景不在 compare/ 中: {', '.join(missing)}", file=sys.stderr)
            return 1
        scenarios = [s for s in scenarios if s in set(args.scenario)]

    metrics = args.metric or DEFAULT_METRICS

    print(
        f"# a(ENO) vs b(Gödel) 延迟对比\n\n"
        f"口径: 3 次 run 逐时间点 nanmedian 聚合（步长 15 s）→ "
        f"剔除首 {args.trim_head} / 尾 {args.trim_tail} 个采样点 → 中位数"
        + (
            "；时序点数不足时回退到 run 级累计直方图分位（口径列标 run）"
            if not args.no_run_total
            else "（已禁用 run 级回退）"
        )
        + "\n"
    )
    records = []
    for metric in metrics:
        print(f"## {metric}\n")
        print(
            f"| 场景 | ENO 样本 | 口径 | {GROUP_LABEL['a']} | {GROUP_LABEL['b']} | 改善 | "
            + ("ENO 逐 run | Gödel 逐 run |" if args.detail else "")
        )
        print(f"|---|---|---|---:|---:|---:|" + ("---|" if args.detail else ""))
        for scenario in scenarios:
            rec = collect(
                scenario,
                metric,
                args.trim_head,
                args.trim_tail,
                allow_run_total=not args.no_run_total,
            )
            records.append(rec)
            a, b = rec["a_value"], rec["b_value"]
            calibers = {
                rec.get("a_caliber", "series"),
                rec.get("b_caliber", "series"),
            }
            caliber = "run" if calibers == {"run-total"} else ("混合" if "run-total" in calibers else "时序")
            row = (
                f"| {scenario} | {rec['a_n']}/{rec['b_n']} | {caliber} | {fmt(a)} | {fmt(b)} | "
                f"{fmt_improve(a, b)} |"
            )
            if args.detail:
                pa = ", ".join(
                    "n/a" if v is None else f"{v:.3f}" for v in rec["a_per_run"]
                )
                pb = ", ".join(
                    "n/a" if v is None else f"{v:.3f}" for v in rec["b_per_run"]
                )
                row += f" {pa} | {pb} |"
            print(row)
        print()

    if args.json:
        Path(args.json).write_text(
            json.dumps(
                {
                    "trim_head": args.trim_head,
                    "trim_tail": args.trim_tail,
                    "results": records,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        print(f"已写出 {args.json}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
