#!/usr/bin/env python3
"""fix-frontmatter-pagenum.py — 让 Word 论文的页码符合规范：

  封面            不显示页码
  前置部分        摘要 / Abstract / 目录 / 插图和附表清单 —— 大写罗马数字 I、II、III…
  正文            第一章起 —— 阿拉伯数字从 1 开始（沿用「- 1 -」样式）

做法：在「第一章」之前插入一个分节符，前置节的 sectPr 设为 upperRoman + start=1、
去掉页眉引用（前置部分不印页眉）；正文节 sectPr 设为 numberInDash + start=1。
封面单独一节（或置于前置节并开启 titlePg）、不引用页脚，因此不显示页码。

用法：
  tools/plot-venv/bin/python docs/thesis/fix-frontmatter-pagenum.py [docx ...]
不传参数时处理 docs/thesis 下的正式版与盲审版两个文件。脚本幂等：已是罗马页码则跳过。
"""

from __future__ import annotations

import copy
import sys
from pathlib import Path

from docx import Document
from lxml import etree

HERE = Path(__file__).resolve().parent
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
DEFAULTS = [
    "基于etcd的分布式Kubernetes调度器研究与实现.docx",
    "基于etcd的分布式Kubernetes调度器研究与实现_盲审.docx",
]


def first_chapter(doc: Document):
    for p in doc.paragraphs:
        if p.style.name in ("Heading 1", "Heading1") and p.text.strip().startswith("第一章"):
            return p
    raise SystemExit("未找到「第一章」标题")


def blank_first_page_footer(doc: Document) -> None:
    """封面若与前置部分同节：开启 titlePg 并清空首页页脚"""
    sec = doc.sections[0]
    sec.different_first_page_header_footer = True
    fpf = sec.first_page_footer
    fpf.is_linked_to_previous = False
    for p in fpf.paragraphs:
        for r in list(p.runs):
            r._r.getparent().remove(r._r)


def patch(path: Path) -> None:
    doc = Document(str(path))
    ch1 = first_chapter(doc)
    prev = ch1._p.getprevious()
    while prev is not None and (prev.tag != W + "p" or not "".join(prev.itertext()).strip()):
        prev = prev.getprevious()
    if prev is None:
        raise SystemExit("第一章之前找不到可承载分节符的段落")

    ppr = prev.find(W + "pPr")
    existing = ppr.find(W + "sectPr") if ppr is not None else None
    if existing is not None:
        pg = existing.find(W + "pgNumType")
        if pg is not None and pg.get(W + "fmt") == "upperRoman":
            print(f"{path.name}: 前置节已是罗马页码，跳过")
            return

    body = doc.element.body
    body_sect = body.find(W + "sectPr")
    if body_sect is None:
        raise SystemExit("缺少正文 sectPr")

    front = copy.deepcopy(body_sect)
    for ref in front.findall(W + "headerReference"):
        front.remove(ref)
    pg = front.find(W + "pgNumType")
    if pg is None:
        pg = etree.SubElement(front, W + "pgNumType")
    pg.set(W + "fmt", "upperRoman")
    pg.set(W + "start", "1")

    if ppr is None:
        ppr = etree.SubElement(prev, W + "pPr")
        prev.insert(0, ppr)
    for old in ppr.findall(W + "sectPr"):
        ppr.remove(old)
    ppr.append(front)

    pg2 = body_sect.find(W + "pgNumType")
    if pg2 is None:
        pg2 = etree.SubElement(body_sect, W + "pgNumType")
    pg2.set(W + "fmt", "numberInDash")
    pg2.set(W + "start", "1")

    doc.save(str(path))
    print(f"{path.name}: 已插入前置分节（前置罗马页码、正文从 1 起）")


def main() -> None:
    targets = [Path(a) for a in sys.argv[1:]] or [HERE / n for n in DEFAULTS]
    for path in targets:
        if not path.exists():
            print(f"跳过（不存在）：{path}")
            continue
        patch(path)


if __name__ == "__main__":
    main()
