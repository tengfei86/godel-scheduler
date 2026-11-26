"""把附表清单的缓存条目按编号升序重排，并重建域字符（begin/instr/separate 在首条、end 在末条）。"""
import re, sys
from pathlib import Path
from docx import Document
from lxml import etree
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def q(t): return f'{W}{t}'
def el(xml): return etree.fromstring(xml.replace('<w:r', f'<w:r xmlns:w="{W[1:-1]}"',1))

for path in [Path(a) for a in sys.argv[1:]]:
    doc=Document(str(path))
    paras=doc.paragraphs
    start=next(i for i,p in enumerate(paras) if p.text.strip()=='附表清单')
    end=next(i for i in range(start+1,len(paras)) if paras[i].style.name.startswith('Heading'))
    block=[p for p in paras[start+1:end] if p.text.strip()]
    # 去掉域字符
    for p in block:
        for e in list(p._p):
            if e.tag==q('r') and (e.find(q('fldChar')) is not None or e.find(q('instrText')) is not None):
                p._p.remove(e)
    # 按编号排序
    def num(p):
        m=re.match(r'表\s*(\d+)', p.text.strip())
        return int(m.group(1)) if m else 999
    ordered=sorted(block, key=num)
    # 重新插入到原位置
    anchor=paras[start]._p
    for p in block: p._p.getparent().remove(p._p)
    for p in ordered:
        anchor.addnext(p._p); anchor=p._p
    # 重建域
    first,last=ordered[0],ordered[-1]
    ppr=first._p.find(q('pPr')); idx=1 if ppr is not None else 0
    for xml in ('<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
                '<w:r><w:instrText xml:space="preserve"> TOC \\h \\z \\t "Caption,1" </w:instrText></w:r>',
                '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'):
        first._p.insert(idx, el(xml))
    last._p.append(el('<w:r><w:fldChar w:fldCharType="end"/></w:r>'))
    doc.save(str(path))
    print(f'{path.name}: 条目重排 {len(ordered)} 条，编号序列 ' + ','.join(str(num(p)) for p in ordered))
