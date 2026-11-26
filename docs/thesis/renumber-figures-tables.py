"""按出现顺序重排图/表编号（通用），并同步正文引用与清单条目。幂等。"""
import re, sys
from pathlib import Path
from docx import Document
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def q(t): return f'{W}{t}'
def el(xml): return etree.fromstring(xml.replace('<w:r', f'<w:r xmlns:w="{W[1:-1]}"',1))
PAT_TPL = r'{label}(\s?)(\d+)(?:(\s*[~-]\s*)(\d+))?'

FIELD = {'图': ' TOC \\h \\z \\c "图" ', '表': ' TOC \\h \\z \\t "Caption,1" '}

def caption_paras(doc, label):
    out=[]
    for p in doc.paragraphs:
        for f in p._p.iter(q('fldSimple')):
            if re.search(rf'SEQ {label} \\r \d+', f.get(q('instr')) or ''):
                out.append(p); break
    return out

def seq_of(p, label):
    for f in p._p.iter(q('fldSimple')):
        m=re.search(rf'SEQ {label} \\r (\d+)', f.get(q('instr')) or '')
        if m: return int(m.group(1))
    return None

def renumber_captions(doc, label, mapping):
    n=0
    for p in caption_paras(doc, label):
        old=seq_of(p,label)
        if old is None or mapping[old]==old: continue
        for f in p._p.iter(q('fldSimple')):
            if re.search(rf'SEQ {label} \\r \d+', f.get(q('instr')) or ''):
                f.set(q('instr'), f' SEQ {label} \\r {mapping[old]} \\* ARABIC ')
                for t in f.iter(q('t')): t.text=str(mapping[old])
        n+=1
    return n

def splice(runs, s, e, new):
    offs=[]; pos=0
    for r in runs:
        offs.append((pos, pos+len(r.text), r)); pos+=len(r.text)
    i=next(k for k,(a,b,_) in enumerate(offs) if a<=s<b)
    j=next(k for k,(a,b,_) in enumerate(offs) if a<e<=b)
    if i==j:
        r=offs[i][2]; t=r.text; st=s-offs[i][0]; en=e-offs[i][0]
        r.text=t[:st]+new+t[en:]
    else:
        r=offs[i][2]; st=s-offs[i][0]; r.text=r.text[:st]+new
        for k in range(i+1,j): offs[k][2].text=''
        rj=offs[j][2]; en=e-offs[j][0]; rj.text=rj.text[en:]

def rewrite_refs(doc, label, mapping, skip):
    pat=re.compile(PAT_TPL.format(label=label))
    changed=0
    for p in doc.paragraphs:
        if p in skip: continue
        runs=[r for r in p.runs if r.text]
        if not runs: continue
        text=''.join(r.text for r in runs)
        ms=[m for m in pat.finditer(text) if int(m.group(2)) in mapping]
        for m in reversed(ms):
            n1=int(m.group(2)); v1=mapping[n1]
            n2=m.group(4); v2=mapping[int(n2)] if n2 and int(n2) in mapping else n2
            if v1==n1 and (n2 is None or v2==int(n2)): continue
            new=f'{label}{m.group(1)}{v1}'
            if n2: new += f'{m.group(3)}{v2}'
            splice(runs, m.start(), m.end(), new); changed+=1
    return changed

def resort_list(doc, label, heading):
    paras=doc.paragraphs
    start=next(i for i,p in enumerate(paras) if p.text.strip()==heading)
    end=next(i for i in range(start+1,len(paras)) if paras[i].style.name.startswith('Heading'))
    block=[p for p in paras[start+1:end] if p.text.strip()]
    if not block: return 0
    for p in block:
        for e in list(p._p):
            if e.tag==q('r') and (e.find(q('fldChar')) is not None or e.find(q('instrText')) is not None):
                p._p.remove(e)
    def num(p):
        m=re.match(rf'{label}\s*(\d+)', p.text.strip())
        return int(m.group(1)) if m else 999
    ordered=sorted(block, key=num)
    anchor=paras[start]._p
    for p in block: p._p.getparent().remove(p._p)
    for p in ordered:
        anchor.addnext(p._p); anchor=p._p
    first,last=ordered[0],ordered[-1]
    ppr=first._p.find(q('pPr')); idx=1 if ppr is not None else 0
    for xml in ('<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
                f'<w:r><w:instrText xml:space="preserve">{FIELD[label]}</w:instrText></w:r>',
                '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'):
        first._p.insert(idx, el(xml))
    last._p.append(el('<w:r><w:fldChar w:fldCharType="end"/></w:r>'))
    return len(ordered)

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path)); print('---', path.name)
    for label, heading in (('图','插图清单'), ('表','附表清单')):
        caps=caption_paras(doc, label)
        order=[seq_of(p,label) for p in caps]
        mapping={old:new for new,old in enumerate(order,1)}
        if all(k==v for k,v in mapping.items()):
            print(f'   {label}: 已按出现顺序（{order[0]}–{order[-1]}），跳过'); continue
        n=renumber_captions(doc, label, mapping)
        ch=rewrite_refs(doc, label, mapping, set(map(id,caps)))
        m=resort_list(doc, label, heading)
        print(f'   {label}: 旧顺序 {order}')
        print(f'      映射 ' + ', '.join(f'{k}→{v}' for k,v in sorted(mapping.items()) if k!=v))
        print(f'      题注 {n} | 引用 {ch} | 清单重排 {m}')
    doc.save(str(path))
