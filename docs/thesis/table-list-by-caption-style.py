"""按测试结论修正：Word 只认 \t "样式名,1"（逗号）。
方案：图题 → 自定义样式「图题注」（继承 Caption）；表题 → 内置 Caption 样式；
      附表清单域 → TOC \h \z \t "Caption,1"（只命中 Caption，不命中继承样式）。
      插图清单保持 \c "图"（按标签，已验证可用）。"""
import re, sys
from pathlib import Path
from docx import Document
from docx.enum.style import WD_STYLE_TYPE
from docx.oxml.ns import qn
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def q(t): return f'{W}{t}'

def has_seq(p, label):
    return any(f'SEQ {label}' in (f.get(W+'instr') or '') for f in p._p.iter(W+'fldSimple'))

def ensure_style(doc, name, base='Caption'):
    for s in doc.styles:
        if s.name==name: return s
    st=doc.styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
    try: st.base_style=doc.styles[base]
    except KeyError: pass
    if st.element.find(qn('w:qFormat')) is None:
        etree.SubElement(st.element, qn('w:qFormat'))
    return st

def ensure_caption(doc):
    # 内置 Caption 样式（中文名 caption）
    for s in doc.styles:
        if s.name.lower()=='caption': return s
    st=doc.styles.add_style('Caption', WD_STYLE_TYPE.PARAGRAPH)
    return st

def retarget(doc):
    c=0
    for it in doc.element.body.iter(q('instrText')):
        t=it.text or ''
        if t.strip().startswith('TOC') and ('表题注' in t or 'c "表"' in t):
            it.text=' TOC \\h \\z \\t "Caption,1" '; c+=1
    return c

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path))
    fig_st=ensure_style(doc,'图题注')
    cap_st=ensure_caption(doc)
    nf=nt=0
    for p in doc.paragraphs:
        if has_seq(p,'图') and p.style.name!='图题注':
            p.style=fig_st; nf+=1
        elif has_seq(p,'表') and p.style.name!='Caption':
            p.style=cap_st; nt+=1
    c=retarget(doc)
    doc.save(str(path))
    print(f'{path.name}: 图题→图题注 {nf} | 表题→Caption {nt} | 域改写 {c}')
