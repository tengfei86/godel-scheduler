"""把「插图清单 / 附表清单」的条目段落包进 TOC 域（\t 指定现有题注样式），
使 Word 更新域后自动生成带页码、可点击跳转的图表目录。"""
from pathlib import Path
from docx import Document
from lxml import etree
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'

def el(xml):
    return etree.fromstring(xml.replace('<w:r', f'<w:r xmlns:w="{W[1:-1]}"', 1))

def wrap(doc, heading_text, style_name, unit):
    paras = doc.paragraphs
    start = next(i for i, p in enumerate(paras) if p.text.strip() == heading_text)
    block = []
    for p in paras[start + 1:]:
        if p.style.name.startswith('Heading'):
            break
        block.append(p)
    entries = [p for p in block if p.text.strip()]
    assert entries, f'{heading_text}: 块内无条目'
    # 只保留以「图/表」开头的首段 + 其后续续行
    instr = f' TOC \\h \\z \\t "{style_name},1" '
    begin = el('<w:r><w:fldChar w:fldCharType="begin"/></w:r>')
    instr_el = el(f'<w:r><w:instrText xml:space="preserve">{instr}</w:instrText></w:r>')
    sep = el('<w:r><w:fldChar w:fldCharType="separate"/></w:r>')
    end = el('<w:r><w:fldChar w:fldCharType="end"/></w:r>')
    first, last = entries[0], entries[-1]
    ppr = first._p.find(W + 'pPr')
    idx = 1 if ppr is not None else 0
    for x in (sep, instr_el, begin):
        first._p.insert(idx, x)
    last._p.append(end)
    return len(entries)

def patch(path: Path):
    doc = Document(str(path))
    print(f'--- {path.name}')
    for heading, style in (('插图清单', 'Image Caption'), ('附表清单', 'Table Caption')):
        try:
            n = wrap(doc, heading, style, heading[0])
            print(f'    {heading}: {n} 段条目 → 已包入 TOC 域（样式 {style}）')
        except StopIteration:
            print(f'    {heading}: 未找到标题，跳过')
    doc.save(str(path))

root = Path('eno/docs/thesis')
for name in ('基于etcd的分布式Kubernetes调度器研究与实现.docx',
             '基于etcd的分布式Kubernetes调度器研究与实现_盲审.docx'):
    patch(root / name)
