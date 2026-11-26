"""按出现顺序重排表号；引用替换支持跨 run 的写法。"""
import re, sys
from pathlib import Path
from docx import Document
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def q(t): return f'{W}{t}'
PAT=re.compile(r'表(\s?)(\d+)(?:(\s*[~-]\s*)(\d+))?')

def caption_paras(doc):
    out=[]
    for p in doc.paragraphs:
        if any('SEQ 表' in (f.get(q('instr')) or '') for f in p._p.iter(q('fldSimple'))):
            out.append(p)
    return out

def order_and_map(doc):
    order=[]
    for p in caption_paras(doc):
        for f in p._p.iter(q('fldSimple')):
            m=re.search(r'SEQ 表 \\r (\d+)', f.get(q('instr')) or '')
            if m: order.append(int(m.group(1))); break
    return order, {old:new for new,old in enumerate(order,1)}

def renumber(doc, mapping):
    n=0
    for p in caption_paras(doc):
        for f in p._p.iter(q('fldSimple')):
            m=re.search(r'SEQ 表 \\r (\d+)', f.get(q('instr')) or '')
            if not m: continue
            new=mapping[int(m.group(1))]
            f.set(q('instr'), f' SEQ 表 \\r {new} \\* ARABIC ')
            for t in f.iter(q('t')): t.text=str(new)
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

def rewrite_refs(doc, mapping):
    changed=0; problems=[]
    targets=[p for p in doc.paragraphs if p not in caption_paras(doc)]
    for tbl in doc.tables:
        for row in tbl.rows:
            for cell in row.cells:
                targets.extend(cell.paragraphs)
    for p in targets:
        runs=[r for r in p.runs if r.text]
        if not runs: continue
        text=''.join(r.text for r in runs)
        matches=[m for m in PAT.finditer(text) if int(m.group(2)) in mapping]
        for m in reversed(matches):
            n1=int(m.group(2)); v1=mapping[n1]
            n2=m.group(4)
            v2=mapping[int(n2)] if n2 and int(n2) in mapping else n2
            if v1==n1 and (n2 is None or v2==int(n2)): continue
            new=f'表{m.group(1)}{v1}'
            if n2: new += f'{m.group(3)}{v2}'
            splice(runs, m.start(), m.end(), new)
            changed+=1
        # 校验：替换后不应残留“旧号→不同新号”的映射
        text2=''.join(r.text for r in runs)
        for m in PAT.finditer(text2):
            if int(m.group(2)) not in mapping.values():
                problems.append((text2[:40], m.group(0)))
    return changed, problems

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path))
    order, mapping = order_and_map(doc)
    n=renumber(doc, mapping)
    ch, prob = rewrite_refs(doc, mapping)
    doc.save(str(path))
    print(f'{path.name}\n   旧顺序 {order}\n   映射 ' + ', '.join(f'{k}→{v}' for k,v in sorted(mapping.items()) if k!=v))
    print(f'   题注 {n} | 引用替换 {ch} | 异常 {len(prob)}')
    for x in prob[:5]: print('     异常:', x)
