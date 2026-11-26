"""把附表清单改为按【样式】收集的 TOC 域：TOC \\h \\z \\t "表题注,1"。
表题统一使用自定义样式「表题注」（名称无空格），避免依赖 Word 的“表”标签注册。"""
import re, sys
from pathlib import Path
from docx import Document
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def q(t): return f'{W}{t}'
def run(xml): return etree.fromstring(xml.replace('<w:r', f'<w:r xmlns:w="{W[1:-1]}"',1))

def clean_block(doc):
    """删掉附表清单条目里旧的 PAGEREF 域与制表位"""
    paras=doc.paragraphs
    start=next(i for i,p in enumerate(paras) if p.text.strip()=='附表清单')
    for p in paras[start+1:]:
        if p.style.name.startswith('Heading'): break
        for el in list(p._p):
            tag=etree.QName(el).localname
            if tag=='fldSimple' and 'PAGEREF' in (el.get(q('instr')) or ''):
                p._p.remove(el)
            elif tag=='r' and el.find(q('tab')) is not None and el.find(q('t')) is None:
                p._p.remove(el)
        ppr=p._p.find(q('pPr'))
        if ppr is not None:
            tabs=ppr.find(q('tabs'))
            if tabs is not None: ppr.remove(tabs)

def wrap_block(doc, instr):
    paras=doc.paragraphs
    start=next(i for i,p in enumerate(paras) if p.text.strip()=='附表清单')
    entries=[]
    for p in paras[start+1:]:
        if p.style.name.startswith('Heading'): break
        if p.text.strip(): entries.append(p)
    first,last=entries[0],entries[-1]
    begin=run('<w:r><w:fldChar w:fldCharType="begin"/></w:r>')
    it=run(f'<w:r><w:instrText xml:space="preserve">{instr}</w:instrText></w:r>')
    sep=run('<w:r><w:fldChar w:fldCharType="separate"/></w:r>')
    end=run('<w:r><w:fldChar w:fldCharType="end"/></w:r>')
    ppr=first._p.find(q('pPr')); idx=1 if ppr is not None else 0
    for x in (sep,it,begin): first._p.insert(idx,x)
    last._p.append(end)
    return len(entries)

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path))
    clean_block(doc)
    n=wrap_block(doc, ' TOC \\h \\z \\t "表题注,1" ')
    doc.save(str(path))
    print(f'{path.name}: 附表清单已改为样式收集（{n} 条）')
