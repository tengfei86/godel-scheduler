#!/usr/bin/env python3
"""postprocess-docx.py — 对 pandoc 生成的 docx 做北航格式后处理

处理内容（依据《北京航空航天大学研究生学位论文撰写规范》2025.3）：

1. 表格宽度铺满版心：pandoc 生成的表格 tblGrid 合计约 13.96 cm，且同时带
   `tblW pct=5000` + `tblLayout fixed`，不同 Word 版本解释不一致，正文里
   看起来表格没有顶到页边距。这里把 tblGrid 与 tblW 统一改成版心宽度（16.00 cm），
   列宽按原比例缩放。
2. 表内段落套用 TableCell 样式（五号宋体居中），替代 pandoc 的 Compact。
3. 分节、页眉与页码（规范 §2.4.2）：
   - 摘要/Abstract/目录 一节：页脚居中大写罗马数字（Ⅰ、Ⅱ…），从 Ⅰ 开始，无页眉；
   - 第一章～第七章：每章一节；奇数页页眉「北京航空航天大学硕士学位论文」，
     偶数页页眉为「章序及章标题」；页码阿拉伯数字从 1 连续编排；
   - 参考文献、附录、致谢：每篇一节，页眉不再分奇偶，均为该篇标题；
   - 页眉与页码均小五号（10.5pt）宋体/Times New Roman，居中。

用法：
  python3 postprocess-docx.py <输入.docx> [<输出.docx>]

若同一目录存在同名输出文件则原地覆盖（默认输入即输出）。
"""

from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path

# ── 常量 ──
TEXT_WIDTH_TWIPS = 9072  # 版心宽 16.00 cm（A4 21cm − 左 2.5 − 右 2.5）
HEADER_ODD_TEXT = "北京航空航天大学硕士学位论文"
HEADER_FONT_SIZE = "21"  # 小五号 = 10.5pt = 21 half-points
NS_W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
# 页眉/页脚根元素的命名空间声明：与北航样例中 Word 原生生成的部件保持一致
NS_BLOCK = (
    'xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" '
    'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    f'xmlns:r="{NS_R}" '
    'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" '
    'xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:w10="urn:schemas-microsoft-com:office:word" '
    f'xmlns:w="{NS_W}" '
    'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" '
    'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" '
    'xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" '
    'xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" '
    'xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml" '
    'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"'
)
CT_HEADER = "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"
CT_FOOTER = "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"
REL_HEADER = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
REL_FOOTER = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
XML_DECL = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


def rpr_runs(text: str) -> str:
    """构造一段带小五号宋体/Times New Roman 的 run"""
    return (
        "<w:r><w:rPr>"
        '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体" w:cs="Times New Roman"/>'
        f'<w:sz w:val="{HEADER_FONT_SIZE}"/><w:szCs w:val="{HEADER_FONT_SIZE}"/>'
        "</w:rPr>"
        f'<w:t xml:space="preserve">{text}</w:t></w:r>'
    )


def header_xml(text: str) -> str:
    rpr = (
        "<w:rPr>"
        '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>'
        f'<w:sz w:val="{HEADER_FONT_SIZE}"/><w:szCs w:val="{HEADER_FONT_SIZE}"/>'
        "</w:rPr>"
    )
    return (
        XML_DECL
        + f'<w:hdr {NS_BLOCK}>'
        + '<w:p><w:pPr><w:jc w:val="center"/>'
        + rpr
        + "</w:pPr>"
        + rpr_runs(text)
        + "</w:p></w:hdr>"
    )


def footer_xml() -> str:
    """页脚：居中 PAGE 域，小五号 Times New Roman，数字两侧不加修饰线"""
    rpr = (
        "<w:rPr>"
        '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>'
        f'<w:sz w:val="{HEADER_FONT_SIZE}"/><w:szCs w:val="{HEADER_FONT_SIZE}"/>'
        "</w:rPr>"
    )
    fld_rpr = (
        "<w:rPr>"
        '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
        f'<w:sz w:val="{HEADER_FONT_SIZE}"/>'
        "</w:rPr>"
    )
    return (
        XML_DECL
        + f'<w:ftr {NS_BLOCK}>'
        + '<w:p><w:pPr><w:jc w:val="center"/>'
        + rpr
        + "</w:pPr>"
        + f"<w:r>{fld_rpr}" + '<w:fldChar w:fldCharType="begin"/></w:r>'
        + '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
        + f"<w:r>{fld_rpr}" + '<w:fldChar w:fldCharType="separate"/></w:r>'
        + rpr_runs("1")
        + f"<w:r>{fld_rpr}" + '<w:fldChar w:fldCharType="end"/></w:r>'
        + "</w:p></w:ftr>"
    )


# ── 步骤 1/2：表格宽度与表内样式 ──
def fix_tables(doc: str) -> str:
    def fix_one(m: re.Match) -> str:
        tbl = m.group(0)
        tbl = re.sub(
            r'<w:pStyle w:val="Compact"\s*/>', '<w:pStyle w:val="TableCell"/>', tbl
        )
        g = re.search(r"<w:tblGrid>(.*?)</w:tblGrid>", tbl, re.S)
        if not g:
            return tbl
        cols = [int(x) for x in re.findall(r'w:w="(\d+)"', g.group(1))]
        if not cols:
            return tbl
        total = sum(cols)
        scaled, acc = [], 0
        for i, c in enumerate(cols):
            v = TEXT_WIDTH_TWIPS - acc if i == len(cols) - 1 else round(c * TEXT_WIDTH_TWIPS / total)
            acc += v
            scaled.append(v)
        new_grid = "<w:tblGrid>" + "".join(f'<w:gridCol w:w="{v}"/>' for v in scaled) + "</w:tblGrid>"
        tbl = tbl[: g.start()] + new_grid + tbl[g.end():]
        tbl = re.sub(
            r'<w:tblW\b[^>]*/>',
            f'<w:tblW w:w="{TEXT_WIDTH_TWIPS}" w:type="dxa"/>',
            tbl,
        )
        # 表格整体居中（Table 样式已有 jc，这里保证存在）
        return tbl

    return re.sub(r"<w:tbl>.*?</w:tbl>", fix_one, doc, flags=re.S)


# ── 步骤 2b：参考文献上标引用改为内部跳转 ──
# 正文写作约定为 <sup>[N]</sup>（构建脚本转成 pandoc 上标 ^\[N\]^），
# pandoc 输出形如：
#   <w:r><w:rPr><w:vertAlign w:val="superscript" /></w:rPr><w:t>[1,2]</w:t></w:r>
# 这里把每个编号拆成指向文献表书签 refN 的内部超链接，并显式覆盖颜色与下划线，
# 使其在版面上仍是普通的黑色上标数字（可点击但不显眼）。
RUN_RE = re.compile(r"<w:r\b[^>]*>.*?</w:r>", re.S)


def citation_rpr(orig_run: str) -> str:
    """按 CT_RPr 的 schema 顺序重建上标数字的 rPr：rFonts → color → u → vertAlign"""
    fonts = re.search(r"<w:rFonts[^>]*/>", orig_run)
    return (
        "<w:rPr>"
        + (fonts.group(0) if fonts else "")
        + '<w:color w:val="auto"/>'
        + '<w:u w:val="none"/>'
        + '<w:vertAlign w:val="superscript"/>'
        + "</w:rPr>"
    )


def link_citations(doc: str) -> tuple[str, int]:
    """把 <sup>[N]</sup> 形式的上标引用改成指向 refN 书签的内部超链接。

    返回 (新文档, 处理的引用条数)。
    """
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        run = m.group(0)
        if "superscript" not in run:
            return run
        t = re.search(r"<w:t[^>]*>([^<]*)</w:t>", run)
        if not t:
            return run
        mm = re.fullmatch(r"\[([\d,\s]+)\]", t.group(1))
        if not mm:
            return run
        nums = [n for n in re.split(r"[,\s]+", mm.group(1).strip()) if n]
        rpr = citation_rpr(run)
        out = []
        for i, n in enumerate(nums):
            if i:
                out.append(f'<w:r>{rpr}<w:t xml:space="preserve">,</w:t></w:r>')
            out.append(
                f'<w:hyperlink w:anchor="ref{n}">'
                f'<w:r>{rpr}<w:t xml:space="preserve">[{n}]</w:t></w:r>'
                f"</w:hyperlink>"
            )
        count += 1
        return "".join(out)

    return RUN_RE.sub(repl, doc), count


# ── 步骤 3：分节 + 页眉页码 ──
# ── 步骤 3：目录移位（规范顺序：中文摘要 → 英文摘要 → 目录 → 正文）──
PAGE_BREAK_BLOCK = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'


def move_toc_after_abstract(doc: str) -> str:
    """pandoc 把目录放在文档最前（摘要之前），规范要求目录在摘要之后、正文之前。

    把开头的 TOCHeading + TOC 域段落整块移到第一个「第…章」标题之前，并在其前加分页符。
    """
    spans = paragraph_spans(doc)
    if not spans:
        return doc
    toc_idx: list[int] = []
    for i, (_s, _e, p) in enumerate(spans[:6]):
        style = para_style(p)
        if style == "TOCHeading" or ("TOC" in p and "fldChar" in p):
            toc_idx.append(i)
        elif toc_idx:
            break
    if not toc_idx:
        return doc
    # 第一个正文章标题
    first_chapter = None
    for s, e, p in spans:
        if para_style(p).startswith("Heading1") and re.match(r"^第.+章", para_text(p)):
            first_chapter = s
            break
    if first_chapter is None or first_chapter < spans[toc_idx[-1]][1]:
        return doc
    start, end = spans[toc_idx[0]][0], spans[toc_idx[-1]][1]
    block = doc[start:end]
    rest = doc[:start] + doc[end:]
    insert_at = first_chapter - (end - start)
    # 目录前保留一个分页符（若原有分页符已在插入点之前则不再重复加，避免空白页）；
    # 目录与第一章之间必须有一个分页符，保证正文从新页开始
    prev_para = None
    for s, e, p in spans:
        if e <= first_chapter:
            prev_para = p
        else:
            break
    leading = "" if (prev_para and 'w:type="page"' in prev_para) else PAGE_BREAK_BLOCK
    moved = leading + block + PAGE_BREAK_BLOCK
    return rest[:insert_at] + moved + rest[insert_at:]


def paragraph_spans(doc: str) -> list[tuple[int, int, str]]:
    """返回文档 body 内每个 <w:p> 的 (start, end, xml)"""
    return [(m.start(), m.end(), m.group(0)) for m in re.finditer(r"<w:p\b.*?</w:p>|<w:p\b[^>]*/>", doc, re.S)]


def para_style(p: str) -> str:
    m = re.search(r'<w:pStyle w:val="([^"]+)"', p)
    return m.group(1) if m else ""


def para_text(p: str) -> str:
    return "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", p)).strip()


def base_sectpr(doc: str) -> str:
    m = re.search(r"<w:sectPr\b.*?</w:sectPr>", doc, re.S)
    return m.group(0) if m else ""


def sect_geometry(sect: str) -> dict[str, str]:
    """从已有 sectPr 取出页面几何元素，按元素名返回（顺序在 build_section 中排定）"""
    out: dict[str, str] = {}
    for tag in ("pgSz", "pgMar", "pgBorders", "cols", "docGrid"):
        mm = re.search(rf"<w:{tag}\b[^>]*/>|<w:{tag}\b.*?</w:{tag}>", sect, re.S)
        if mm:
            out[tag] = mm.group(0)
    return out


def build_section(
    geometry: dict[str, str],
    pg_num: str | None,
    odd_rid: str | None,
    even_rid: str | None,
    footer_rid: str | None,
) -> str:
    """组装 sectPr。

    子元素顺序必须符合 CT_SectPr 的 schema 序列，否则 Word 会报
    "Word experienced an error trying to open the file"：
      headerReference* → footerReference* → pgSz → pgMar → pgBorders
      → pgNumType → cols → docGrid
    （顺序以北航样例中 Word 原生生成的 sectPr 为准）
    """
    parts = ["<w:sectPr>"]
    if odd_rid:
        parts.append(f'<w:headerReference w:type="default" r:id="{odd_rid}"/>')
    if even_rid:
        parts.append(f'<w:headerReference w:type="even" r:id="{even_rid}"/>')
    if footer_rid:
        parts.append(f'<w:footerReference w:type="default" r:id="{footer_rid}"/>')
        parts.append(f'<w:footerReference w:type="even" r:id="{footer_rid}"/>')
    for tag in ("pgSz", "pgMar", "pgBorders"):
        if tag in geometry:
            parts.append(geometry[tag])
    if pg_num:
        parts.append(pg_num)
    for tag in ("cols", "docGrid"):
        if tag in geometry:
            parts.append(geometry[tag])
    parts.append("</w:sectPr>")
    return "".join(parts)


def insert_sectpr(paragraph: str, sectpr: str) -> str:
    """把 sectPr 放到该段落的 pPr 末尾（sectPr 必须是 pPr 的最后一个子元素）"""
    m = re.search(r"<w:pPr>(.*?)</w:pPr>", paragraph, re.S)
    if m:
        return paragraph[: m.end() - len("</w:pPr>")] + sectpr + paragraph[m.end() - len("</w:pPr>"):]
    # 无 pPr：在 <w:p ...> 之后插入
    m2 = re.match(r"<w:p\b[^>]*>", paragraph)
    if not m2:
        return paragraph
    return paragraph[: m2.end()] + f"<w:pPr>{sectpr}</w:pPr>" + paragraph[m2.end():]


def process(input_path: Path, output_path: Path, conservative: bool = False) -> None:
    tmp = output_path.parent / "_pp_tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    with zipfile.ZipFile(input_path) as z:
        z.extractall(tmp)

    doc_file = tmp / "word/document.xml"
    doc = doc_file.read_text(encoding="utf-8")
    doc = fix_tables(doc)
    doc, cite_n = link_citations(doc)
    if conservative:
        # 保守模式：只做表格宽度与表内样式，不重建分节、页眉页码，也不移动目录。
        # 用于排查 Word 无法打开的问题（该模式下输出与历史可正常打开的版本同类）。
        doc_file.write_text(doc, encoding="utf-8")
        _repackage(tmp, output_path)
        print(f"后处理完成（保守模式）：表格铺满版心 + 表内五号居中 + {cite_n} 处文献引用改为内部跳转；未改动分节/页眉/页码")
        return
    doc = move_toc_after_abstract(doc)

    # 定位章节：Heading1 段落；正文起点为第一个以「第…章」开头的 Heading1
    spans = paragraph_spans(doc)
    chapters: list[tuple[int, int, str]] = []  # (段落序号, 段内 end 偏移, 标题)
    for i, (s, e, p) in enumerate(spans):
        if para_style(p).startswith("Heading1"):
            chapters.append((i, e, para_text(p)))
    if not chapters:
        doc_file.write_text(doc, encoding="utf-8")
        _repackage(tmp, output_path)
        print("警告：未找到一级标题，跳过页眉页码分节")
        return

    body_start = 0
    for idx, (pi, _e, title) in enumerate(chapters):
        if re.match(r"^第.+章", title):
            body_start = idx
            break

    # 分节边界：front matter 末段 + 每章末段
    # 「section i」= [boundary_prev+1, boundary_i]
    front_end_para = chapters[body_start][0] - 1 if body_start > 0 else -1
    chap_last_para = []
    for idx in range(len(chapters)):
        if idx + 1 < len(chapters):
            chap_last_para.append(chapters[idx + 1][0] - 1)
        else:
            chap_last_para.append(len(spans) - 1)

    # 部件与关系
    rels_file = tmp / "word/_rels/document.xml.rels"
    rels_xml = rels_file.read_text(encoding="utf-8")
    ct_file = tmp / "[Content_Types].xml"
    ct_xml = ct_file.read_text(encoding="utf-8")

    # 清掉参考模板遗留的 header/footer 部件与关系
    for f in list((tmp / "word").glob("header*.xml")) + list((tmp / "word").glob("footer*.xml")):
        f.unlink()
    rels_xml = re.sub(
        r'<Relationship [^>]*Type="[^"]*/(?:header|footer)"[^>]*/>', "", rels_xml
    )
    ct_xml = re.sub(
        r'<Override PartName="/word/(?:header|footer)\d+\.xml"[^>]*/>', "", ct_xml
    )

    geometry = sect_geometry(base_sectpr(doc))
    rel_map: dict[str, str] = {}
    new_rels: list[str] = []
    new_parts: list[tuple[str, str, str]] = []  # (part name, content type, xml)
    used_ids = set(re.findall(r'Id="([^"]+)"', rels_xml))
    counter = [0]

    def next_rid() -> str:
        while True:
            counter[0] += 1
            rid = f"rIdPp{counter[0]}"
            if rid not in used_ids:
                used_ids.add(rid)
                return rid

    def add_header(name: str, text: str) -> str:
        part = f"header_pp_{name}.xml"
        rid = next_rid()
        new_rels.append(
            f'<Relationship Id="{rid}" Type="{REL_HEADER}" Target="{part}"/>'
        )
        new_parts.append((part, CT_HEADER, header_xml(text)))
        return rid

    def add_footer() -> str:
        part = "footer_pp_page.xml"
        rid = next_rid()
        new_rels.append(
            f'<Relationship Id="{rid}" Type="{REL_FOOTER}" Target="{part}"/>'
        )
        new_parts.append((part, CT_FOOTER, footer_xml()))
        return rid

    footer_rid = add_footer()
    odds: dict[str, str] = {}

    # 各节的 header/footer 引用与页码格式
    sections: list[str] = []
    # 1) front matter
    if front_end_para >= 0:
        sections.append(
            build_section(
                geometry,
                '<w:pgNumType w:fmt="upperRoman" w:start="1"/>',
                None,
                None,
                footer_rid,
            )
        )
    # 2) 正文各章
    for idx in range(body_start, len(chapters)):
        title = chapters[idx][2]
        if re.match(r"^(参考文献|附录|致谢)", title):
            rid = odds.setdefault(title, add_header(f"same{idx}", title))
            sections.append(
                build_section(
                    geometry,
                    '<w:pgNumType w:fmt="decimal" w:start="1"/>' if idx == body_start else None,
                    rid,
                    rid,
                    footer_rid,
                )
            )
        else:
            odd_rid = odds.setdefault("__odd__", add_header("odd", HEADER_ODD_TEXT))
            even_rid = odds.setdefault(f"__even{idx}__", add_header(f"ch{idx}", title))
            sections.append(
                build_section(
                    geometry,
                    '<w:pgNumType w:fmt="decimal" w:start="1"/>' if idx == body_start else None,
                    odd_rid,
                    even_rid,
                    footer_rid,
                )
            )

    # 把 sectPr 写进各节末段（最后一节留在 body 级 sectPr）
    all_bounds = ([front_end_para] if front_end_para >= 0 else []) + chap_last_para[body_start:]
    sec_idx = 0
    out = []
    prev_end = 0
    for pi, (s, e, p) in enumerate(spans):
        if pi in all_bounds and sec_idx < len(sections) - 1:
            out.append(doc[prev_end:s])
            out.append(insert_sectpr(p, sections[sec_idx]))
            prev_end = e
            sec_idx += 1
    # 文末余下部分含 body 级 sectPr（即最后一节），就地替换；
    # 不能用全局 re.sub(count=1)，否则会误替换前面刚插入的分节属性
    tail = re.sub(
        r"<w:sectPr\b.*?</w:sectPr>", sections[-1], doc[prev_end:], count=1, flags=re.S
    )
    out.append(tail)
    doc = "".join(out)

    doc_file.write_text(doc, encoding="utf-8")

    # 写关系与内容类型
    if new_rels:
        rels_xml = rels_xml.replace("</Relationships>", "".join(new_rels) + "</Relationships>")
    rels_file.write_text(rels_xml, encoding="utf-8")
    overrides = "".join(
        f'<Override PartName="/word/{part}" ContentType="{ct}"/>' for part, ct, _ in new_parts
    )
    ct_xml = ct_xml.replace("</Types>", overrides + "</Types>")
    ct_file.write_text(ct_xml, encoding="utf-8")
    for part, _ct, xml in new_parts:
        (tmp / "word" / part).write_text(xml, encoding="utf-8")

    _repackage(tmp, output_path)
    print(
        f"后处理完成：表格宽度统一为 {TEXT_WIDTH_TWIPS} twips（16.00 cm）；"
        f"分 {len(sections)} 节（含 {sum(1 for s in sections if 'upperRoman' in s)} 节罗马页码），"
        f"新增页眉/页脚部件 {len(new_parts)} 个；{cite_n} 处文献引用改为内部跳转"
    )


def _repackage(tmp: Path, output_path: Path) -> None:
    if output_path.exists():
        output_path.unlink()
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(tmp.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(tmp))
    shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if not args:
        print(__doc__)
        return 1
    src = Path(args[0])
    dst = Path(args[1]) if len(args) > 1 else src
    process(src, dst, conservative="--conservative" in flags)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
