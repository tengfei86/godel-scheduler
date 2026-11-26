"""图题/表题 → Word 正式题注（Caption 样式 + SEQ 域，带 \\r 固定编号），外观保持原样；
插图/附表清单域 → TOC \\c "图" / \\c "表"。"""
import re, sys
from pathlib import Path
from docx import Document
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
XMLSPACE='{http://www.w3.org/XML/1998/namespace}space'
def q(t): return f'{W}{t}'
def add(parent, tag, **kw):
    e=etree.SubElement(parent, q(tag))
    for k,v in kw.items(): e.set(q(k), str(v))
    return e
def rpr(b=True, sz=21):
    r=etree.Element(q('rPr'))
    if b: etree.SubElement(r, q('b'))
    add(r,'sz',val=sz); add(r,'szCs',val=sz); return r
def mkrun(text):
    r=etree.Element(q('r')); r.append(rpr())
    t=etree.SubElement(r, q('t')); t.text=text; t.set(XMLSPACE,'preserve'); return r

def convert(doc):
    n=0
    for p in doc.paragraphs:
        if p.style.name not in ('Image Caption','Table Caption'): continue
        m=re.match(r'^\s*(图|表)\s*(\d+)', p.text)
        if not m: continue
        label, num = m.group(1), m.group(2)
        target=None
        for r in p.runs:
            if num in r.text and r.text.strip():
                target=r; break
        if target is None: continue
        txt=target.text; i=txt.find(num)
        prefix, suffix = txt[:i], txt[i+len(num):]
        fld=etree.Element(q('fldSimple'))
        fld.set(q('instr'), f' SEQ {label} \\r {num} \\* ARABIC ')
        fr=etree.SubElement(fld, q('r')); fr.append(rpr())
        ft=etree.SubElement(fr, q('t')); ft.text=num
        anchor=target._r; parent=anchor.getparent(); pos=list(parent).index(anchor)
        parent.remove(anchor)
        new=[]
        if prefix: new.append(mkrun(prefix))
        new.append(fld)
        if suffix: new.append(mkrun(suffix))
        for off,el in enumerate(new): parent.insert(pos+off, el)
        ppr=p._p.find(q('pPr'))
        ppr.find(q('pStyle')).set(q('val'),'Caption')
        before,after=('120','240') if p.style.name=='Image Caption' else ('240','120')
        sp=ppr.find(q('spacing'))
        if sp is None: sp=add(ppr,'spacing')
        sp.set(q('before'),before); sp.set(q('after'),after)
        jc=ppr.find(q('jc'))
        if jc is None: jc=add(ppr,'jc')
        jc.set(q('val'),'center')
        for r in p.runs:
            rp=r._r.find(q('rPr'))
            if rp is None: rp=etree.Element(q('rPr')); r._r.insert(0,rp)
            if rp.find(q('b')) is None: etree.SubElement(rp, q('b'))
            for tag in ('sz','szCs'):
                e=rp.find(q(tag))
                if e is None: e=add(rp,tag)
                e.set(q('val'),'21')
        n+=1
    return n

def retarget(doc):
    c=0
    for it in doc.element.body.iter(q('instrText')):
        t=it.text or ''
        if 'TOC' not in t: continue
        if 'Image Caption' in t: it.text=' TOC \\h \\z \\c "图" '; c+=1
        elif 'Table Caption' in t: it.text=' TOC \\h \\z \\c "表" '; c+=1
    return c

def rendered(p):
    """把 fldSimple 的缓存文本拼回来，用于校验可见文字"""
    out=[]
    for ch in p._p:
        tag=etree.QName(ch).localname
        if tag=='r':
            out.append(''.join(t.text or '' for t in ch.iter(q('t'))))
        elif tag=='fldSimple':
            out.append(''.join(t.text or '' for t in ch.iter(q('t'))))
    return ''.join(out)

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path))
    before=[(i,rendered(p)) for i,p in enumerate(doc.paragraphs)]
    n=convert(doc); f=retarget(doc)
    after=[(i,rendered(p)) for i,p in enumerate(doc.paragraphs)]
    diff=[(i,a,b) for (i,a),(_,b) in zip(before,after) if a!=b]
    doc.save(str(path))
    print(f'{path.name}: 题注 {n} 处 | 清单域 {f} 处 | 可见文字差异 {len(diff)} 处')
    for d in diff[:3]: print('    ', d)
