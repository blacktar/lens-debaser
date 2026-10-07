#!/usr/bin/env python3
"""Check the complete guide before review or upload packaging."""
from pathlib import Path
from html.parser import HTMLParser
from collections import Counter
r=Path(__file__).resolve().parents[1];guide=r/'docs/user-guide/Lens-Debaser-User-Guide.html'
class Audit(HTMLParser):
 def __init__(self):super().__init__();self.ids=[];self.images=[];self.links=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if a.get('id'):self.ids.append(a['id'])
  if tag=='img':self.images.append(a.get('src',''))
  if tag=='a' and a.get('href','').startswith('#'):self.links.append(a['href'][1:])
a=Audit();a.feed(guide.read_text());duplicates=[x for x,n in Counter(a.ids).items() if n>1];missing=[x for x in a.links if x not in a.ids];assert not duplicates,duplicates;assert not missing,missing
assert sum(x.startswith('preset-example-') for x in a.ids)==88
assert len([x for x in a.images if '/preset-' in x])==440
assert 'demo-presets' in a.ids and 'example-final-framing' in a.ids
bad=[x for x in a.images if x.endswith('render-pending.svg') or not (guide.parent/x).exists()];assert not bad,f'{len(bad)} missing images; run ./scripts/render-guide-1.72.sh'
print('PASS: 88 cinematic presets / 440 renders; all images, links and unique anchors present.')
