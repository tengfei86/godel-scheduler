"""附表清单：静态条目 + PAGEREF 域 + 书签（绕过 Word 的“表”标签识别问题）。
表题样式统一为自定义「表题注」，编号取自其 SEQ 域。"""
import re, sys
from pathlib import Path
from docx import Document
from docx.enum.style import WD_STYLE_TYPE
from docx.oxml.ns import qn
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def q(t): return f'{W}{t}'
def add(parent, tag, **kw):
    e=etree.SubElement(parent, q(tag))
    for k,v in kw.items(): e.set(q(k), str(v))
    return e
def seq_num(p, label='表'):
    for f in p._p.iter(q('fldSimple')):
        ins=f.get(q('instr')) or ''
        m=re.search(rf'SEQ {label} \\r (\d+)', ins)
        if m: return m.group(1)
    return None

def ensure_style(doc, name='表题注'):
    for st in doc.styles:
        if st.name==name: return st
    st=doc.styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
    try: st.base_style=doc.styles['Caption']
    except KeyError: pass
    if st.element.find(qn('w:qFormat')) is None:
        etree.SubElement(st.element, qn('w:qFormat'))
    return st

def mark_tables(doc, style):
    n=0; ids=[]
    for p in doc.paragraphs:
        num=seq_num(p,'表')
        if not num: continue
        p.style=style
        if p._p.find(q('bookmarkStart')) is None:
            bid=1000+int(num)
            bs=etree.Element(q('bookmarkStart')); bs.set(q('id'),str(bid)); bs.set(q('name'),f'_Tbl{num}')
            be=etree.Element(q('bookmarkEnd')); be.set(q('id'),str(bid))
            ppr=p._p.find(q('pPr'))
            p._p.insert(1 if ppr is not None else 0, bs); p._p.append(be)
        ids.append(num); n+=1
    return n, sorted(set(ids), key=int)

def rebuild_list(doc):
    paras=doc.paragraphs
    start=next(i for i,p in enumerate(paras) if p.text.strip()=='附表清单')
    removed=0
    for p in paras[start+1:]:
        if p.style.name.startswith('Heading'): break
        for el in list(p._p):
            if el.tag==q('r') and (el.find(q('fldChar')) is not None or el.find(q('instrText')) is not None):
                p._p.remove(el); removed+=1
    added=0
    for p in paras[start+1:]:
        if p.style.name.startswith('Heading'): break
        m=re.match(r'^表\s*(\d+)', p.text.strip())
        if not m: continue
        num=m.group(1)
        ppr=p._p.find(q('pPr'))
        if ppr is None:
            ppr=etree.Element(q('pPr')); p._p.insert(0,ppr)
        tabs=ppr.find(q('tabs')) or add(ppr,'tabs')
        if tabs.find(q('tab')) is None:
            t=add(tabs,'tab'); t.set(q('val'),'right'); t.set(q('leader'),'dot'); t.set(q('pos'),'9060')
        r=etree.SubElement(p._p, q('r')); etree.SubElement(r, q('tab'))
        fld=etree.SubElement(p._p, q('fldSimple')); fld.set(q('instr'), f' PAGEREF _Tbl{num} \\h ')
        fr=etree.SubElement(fld, q('r')); etree.SubElement(fr, q('t')).text=num
        added+=1
    return removed, added

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path))
    st=ensure_style(doc)
    n, ids = mark_tables(doc, st)
    removed, added = rebuild_list(doc)
    doc.save(str(path))
    print(f'{path.name}\n   表题样式/书签: {n} 个（编号 {ids[0]}–{ids[-1]}）| 清理旧域字符 {removed} | 写入 PAGEREF {added}')
