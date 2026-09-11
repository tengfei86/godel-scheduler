#!/usr/bin/env python3
"""
make-reference.py — 生成符合北航规范的 pandoc 参考模板 docx

背景：直接以学校样例 docx 作为 --reference-doc 时，pandoc 需要的一批样式名
（Body Text / First Paragraph / Compact / Image Caption / Table / Block Text /
TOC Heading 等）在样例中并不存在，导致正文缩进、图题、三线表、目录标题等
全部回退为默认样式。本脚本以样例为基底，注入这些样式（格式依据《北京航空
航天大学研究生学位论文撰写规范 2025.3》），并修正页边距。

用法：
    python3 make-reference.py [样例docx路径] [输出路径]
默认：
    输入 ../standard/附件7-2：学位论文样例（word）版.docx
    输出 beihang-reference.docx
"""

import re
import shutil
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "standard" / "附件7-2：学位论文样例（word）版.docx"
DST = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "beihang-reference.docx"

CN_PT = 2  # 1pt = 2 half-points

def rpr(font_cn, size_pt, bold=False, font_en="Times New Roman"):
    """构造 run 属性：中文字体 / 西文字体 / 字号（半磅）"""
    b = "<w:b/>" if bold else ""
    return (
        f'<w:rPr><w:rFonts w:ascii="{font_en}" w:hAnsi="{font_en}" '
        f'w:eastAsia="{font_cn}"/><w:sz w:val="{int(size_pt*CN_PT)}"/>'
        f'<w:szCs w:val="{int(size_pt*CN_PT)}"/>{b}</w:rPr>'
    )

# ── 需要注入的样式（依据北航规范 2.3.5 / 2.3.7 / 2.3.9 / 2.3.10 / 2.3.18）──
STYLES = f"""
<w:style w:type="paragraph" w:styleId="BodyText"><w:name w:val="Body Text"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:jc w:val="both"/><w:ind w:firstLineChars="200" w:firstLine="480"/><w:spacing w:before="0" w:after="0" w:line="360" w:lineRule="auto"/></w:pPr>
{rpr("宋体", 12)}</w:style>
<w:style w:type="paragraph" w:styleId="FirstParagraph"><w:name w:val="First Paragraph"/><w:basedOn w:val="BodyText"/><w:qFormat/>
<w:pPr><w:jc w:val="both"/><w:ind w:firstLineChars="200" w:firstLine="480"/><w:spacing w:line="360" w:lineRule="auto"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Compact"><w:name w:val="Compact"/><w:basedOn w:val="BodyText"/><w:qFormat/>
<w:pPr><w:jc w:val="both"/><w:ind w:firstLineChars="0" w:firstLine="0" w:leftChars="200" w:left="480"/><w:spacing w:line="360" w:lineRule="auto"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/>
<w:pPr><w:keepNext/><w:jc w:val="center"/><w:outlineLvl w:val="0"/><w:spacing w:beforeLines="50" w:afterLines="50" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("黑体", 16)}</w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="Heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/>
<w:pPr><w:keepNext/><w:jc w:val="left"/><w:outlineLvl w:val="1"/><w:spacing w:beforeLines="50" w:afterLines="50" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("黑体", 14)}</w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="Heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/>
<w:pPr><w:keepNext/><w:jc w:val="left"/><w:outlineLvl w:val="2"/><w:spacing w:beforeLines="50" w:afterLines="50" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("黑体", 12)}</w:style>
<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="Heading 4"/><w:basedOn w:val="Heading3"/><w:qFormat/>
<w:pPr><w:outlineLvl w:val="3"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="ImageCaption"><w:name w:val="Image Caption"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="240" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("宋体", 10.5, bold=True)}</w:style>
<w:style w:type="paragraph" w:styleId="TableCaption"><w:name w:val="Table Caption"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:jc w:val="center"/><w:spacing w:before="240" w:after="120" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("宋体", 10.5, bold=True)}</w:style>
<w:style w:type="paragraph" w:styleId="CaptionedFigure"><w:name w:val="Captioned Figure"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:jc w:val="center"/><w:spacing w:before="120" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="BlockText"><w:name w:val="Block Text"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:ind w:leftChars="200" w:left="420"/><w:spacing w:before="60" w:after="60" w:line="300" w:lineRule="auto"/></w:pPr>
{rpr("宋体", 10.5)}</w:style>
<w:style w:type="paragraph" w:styleId="SourceCode"><w:name w:val="Source Code"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:ind w:leftChars="100" w:left="210"/><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>
<w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:eastAsia="宋体"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="TOCHeading"><w:name w:val="TOC Heading"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:jc w:val="center"/><w:spacing w:beforeLines="50" w:afterLines="50" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("黑体", 18, bold=True)}</w:style>
<w:style w:type="paragraph" w:styleId="TOC1"><w:name w:val="TOC 1"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:spacing w:line="360" w:lineRule="auto"/></w:pPr>{rpr("黑体", 12)}</w:style>
<w:style w:type="paragraph" w:styleId="TOC2"><w:name w:val="TOC 2"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:ind w:leftChars="100" w:left="210"/><w:spacing w:line="360" w:lineRule="auto"/></w:pPr>{rpr("黑体", 12)}</w:style>
<w:style w:type="paragraph" w:styleId="TOC3"><w:name w:val="TOC 3"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:ind w:leftChars="200" w:left="420"/><w:spacing w:line="360" w:lineRule="auto"/></w:pPr>{rpr("宋体", 10.5)}</w:style>
<w:style w:type="paragraph" w:styleId="Bibliography"><w:name w:val="Bibliography"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:ind w:leftChars="200" w:left="420" w:hangingChars="200" w:hanging="420"/><w:spacing w:before="60" w:after="0" w:line="320" w:lineRule="exact"/></w:pPr>
{rpr("宋体", 10.5)}</w:style>
<w:style w:type="paragraph" w:styleId="FootnoteText"><w:name w:val="Footnote Text"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:ind w:hangingChars="150" w:hanging="315"/><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>
{rpr("宋体", 9)}</w:style>
<w:style w:type="table" w:styleId="Table"><w:name w:val="Table"/><w:basedOn w:val="TableNormal"/><w:qFormat/>
<w:tblPr><w:jc w:val="center"/><w:tblBorders>
<w:top w:val="single" w:sz="12" w:space="0" w:color="auto"/>
<w:bottom w:val="single" w:sz="12" w:space="0" w:color="auto"/>
<w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>
<w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>
<w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/>
<w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr>
<w:tcPr><w:vAlign w:val="center"/></w:tcPr>
<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr>
<w:tcPr><w:tcBorders><w:bottom w:val="single" w:sz="8" w:space="0" w:color="auto"/></w:tcBorders></w:tcPr>
</w:tblStylePr></w:style>
"""

def main():
    tmp = HERE / "_ref_tmp"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir()
    with zipfile.ZipFile(SRC) as z:
        z.extractall(tmp)
    shutil.copytree(tmp, HERE / "_ref_out", dirs_exist_ok=True)
    out = HERE / "_ref_out"

    # 1) 注入样式（去掉同名旧样式，避免重复 styleId）
    sp = out / "word" / "styles.xml"
    sx = sp.read_text(encoding="utf-8")
    ids = re.findall(r'w:styleId="([^"]+)"', STYLES)
    for sid in set(ids):
        sx = re.sub(r'<w:style [^>]*w:styleId="' + re.escape(sid) + r'".*?</w:style>', '', sx, flags=re.S)
    # 去掉样例中同名的 heading/Body Text 旧样式（按 name 匹配）
    for nm in ["Body Text", "heading 1", "heading 2", "heading 3", "heading 4", "caption"]:
        sx = re.sub(r'<w:style [^>]*>\s*<w:name w:val="' + re.escape(nm) + r'"/>.*?</w:style>', '', sx, flags=re.S)
    sx = sx.replace("</w:styles>", STYLES + "</w:styles>")
    sp.write_text(sx, encoding="utf-8")

    # 2) 页边距：A4 + 四边距 2.5cm(1417) + 页眉页脚 1.5cm(851)
    for f in out.glob("word/*.xml"):
        t = f.read_text(encoding="utf-8")
        t2 = re.sub(
            r'<w:pgMar [^/]*/>',
            '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
            'w:header="851" w:footer="851" w:gutter="0"/>',
            t)
        t2 = re.sub(r'<w:pgSz [^/]*/>', '<w:pgSz w:w="11906" w:h="16838"/>', t2)
        if t2 != t:
            f.write_text(t2, encoding="utf-8")

    # 3) 打包
    if DST.exists():
        DST.unlink()
    with zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(out))
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.rmtree(out, ignore_errors=True)
    print(f"已生成参考模板：{DST}")
    print(f"  注入样式：{', '.join(sorted(set(ids)))}")

if __name__ == "__main__":
    main()
