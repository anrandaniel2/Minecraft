import re
with open('/tmp/sample.html','r',errors='ignore') as f:
    html=f.read()
    scripts=re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)
    js=''.join(scripts)[:1000000]
    open('decompiled/out/sample_teavm.js','w',encoding='utf-8',errors='ignore').write(js[:500000])
    print(f'Extracted {len(js)} chars')
