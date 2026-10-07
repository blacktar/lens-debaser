#!/usr/bin/env python3
from pathlib import Path
import hashlib, html, re, sys

root=Path(sys.argv[1] if len(sys.argv)>1 else "outputs/experiments/projection-models")
images=root/"images"
models=[("equidistant","Equidistant"),("equisolid","Equisolid angle"),
        ("stereographic","Stereographic"),("orthographic","Orthographic")]
sources=[("iso","ISO chart"),("optical","Synthetic optical chart"),
         ("milano1","Milano 1"),("milano2","Milano 2"),("milano3","Milano 3")]

def require_changed(before,after,label):
    before_path=root/before
    after_path=root/after
    if not before_path.exists() or not after_path.exists():
        raise SystemExit(f"Missing comparison image: {before} or {after}")
    digest=lambda path: hashlib.sha256(path.read_bytes()).digest()
    if digest(before_path)==digest(after_path):
        raise SystemExit(f"Invalid comparison: byte-identical images for {label}")

bench=(root/"benchmark.txt").read_text(errors="replace") if (root/"benchmark.txt").exists() else ""
rows=[]
for slug,label in models:
    base=re.search(rf"^{slug}-base\s+GPU\s+([0-9.]+) ms\s+wall\s+([0-9.]+)",bench,re.M)
    test=re.search(rf"^{slug}-test\s+GPU\s+([0-9.]+) ms\s+wall\s+([0-9.]+)",bench,re.M)
    if base and test:
        bg,bw,tg,tw=map(float,(*base.groups(),*test.groups()))
        rows.append(f"<tr><th>{label}</th><td>{bg:.3f} ms</td><td>{tg:.3f} ms</td>"
                    f"<td>{(tg/bg-1)*100:+.1f}%</td><td>{bw:.3f} ms</td>"
                    f"<td>{tw:.3f} ms</td><td>{(tw/bw-1)*100:+.1f}%</td></tr>")

cards=[]
cards.append('''<section><p class="eyebrow">FRAMING BEHAVIOUR</p><h2>Projection character without forced magnification</h2><p>These focused equidistant comparisons hold projection angle and amount constant. Full-frame preservation keeps the complete source boundary but magnifies the centre. Balanced framing shares that cost between centre and perimeter. Centre-scale preservation keeps the centre at its original size and lets the transformed perimeter extend beyond the available source. Boundary-safe centre scale preserves that central geometry but progressively limits displacement near unavailable source pixels to avoid clamped streaks and empty edges.</p>''')
for source,source_label in (("iso","ISO chart"),("milano1","Milano 1")):
    for slug,label in (("full-frame","Preserve full frame"),("balanced","Balanced framing"),("center-scale","Preserve centre scale"),("boundary-safe","Boundary-safe centre scale")):
        before=f"images/baseline-geometry-{source}.png"
        after=f"images/framing-{slug}-{source}.png"
        require_changed(before,after,f"{source} / {label}")
        cards.append(f'''<article><h3>{source_label} · {label}</h3>
<div class="compare" style="--split:50%"><img src="{before}" alt="Released baseline">
<div class="after"><img src="{after}" alt="{html.escape(label)}"></div>
<span class="line"></span><input type="range" min="0" max="100" value="50" aria-label="Comparison position"></div>
<p><b>Left:</b> released baseline · <b>Right:</b> {label}</p></article>''')
cards.append('</section>')
for slug,label in models:
    cards.append(f'<section><p class="eyebrow">{label.upper()}</p><h2>{label}</h2>')
    for source,source_label in sources:
        for kind,kind_label in (("geometry","Projection only"),("optical","Projection-aware optics")):
            before=f"images/baseline-{kind}-{source}.png"
            after=f"images/{slug}-{kind}-{source}.png"
            require_changed(before,after,f"{slug} / {kind} / {source}")
            cards.append(f'''<article><h3>{source_label} · {kind_label}</h3>
<div class="compare" style="--split:50%"><img src="{before}" alt="Released baseline">
<div class="after"><img src="{after}" alt="{html.escape(label)} candidate"></div>
<span class="line"></span><input type="range" min="0" max="100" value="50" aria-label="Comparison position"></div>
<p><b>Left:</b> released baseline · <b>Right:</b> {label} candidate</p></article>''')
    cards.append('</section>')

document=f'''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Lens Debaser projection experiment</title>
<style>:root{{--ink:#f4f7f8;--muted:#9eb0b5;--panel:#11191c;--acid:#16cbf6}}*{{box-sizing:border-box}}body{{margin:0;background:#071013;color:var(--ink);font:16px/1.55 system-ui,sans-serif}}header,main{{width:min(1500px,94vw);margin:auto}}header{{padding:64px 0 30px}}h1{{font-size:clamp(2.6rem,7vw,7rem);line-height:.9;margin:.2em 0}}h2{{font-size:2rem}}.eyebrow{{color:var(--acid);font-weight:800;letter-spacing:.12em}}section{{border-top:1px solid #274047;padding:28px 0}}article{{background:var(--panel);padding:18px;margin:18px 0;border-radius:12px}}.compare{{position:relative;overflow:hidden;background:#000;aspect-ratio:16/9}}.compare img{{display:block;width:100%;height:100%;object-fit:contain}}.after{{position:absolute;inset:0;clip-path:inset(0 0 0 var(--split))}}.line{{position:absolute;left:var(--split);top:0;bottom:0;width:2px;background:var(--acid);transform:translateX(-1px)}}input{{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:ew-resize}}table{{width:100%;border-collapse:collapse;background:var(--panel)}}th,td{{padding:12px;border-bottom:1px solid #274047;text-align:right}}th:first-child{{text-align:left}}p{{color:var(--muted)}}</style></head>
<body><header><p class="eyebrow">NON-PROMOTED EXPERIMENT</p><h1>Projection model<br>comparison</h1><p>Exact ideal inverse mappings at a shared 55° half-diagonal field angle and 45% blend. Each model is normalized by its own radius at that field angle, giving every projection the same optical-axis scale rather than allowing one formula to inherit another model’s magnification. The main comparisons use boundary-safe centre-scale framing: central geometry is preserved while displacement is progressively limited near unavailable source pixels. Geometry-only cards isolate image-density redistribution. Projection-aware cards apply the same field softness and chromatic recipe on both sides so the candidate’s interaction with downstream optics is visible.</p></header><main>
<section><h2>1920×1080 performance</h2><table><thead><tr><th>Model</th><th>Baseline GPU</th><th>Candidate GPU</th><th>GPU change</th><th>Baseline wall</th><th>Candidate wall</th><th>Wall change</th></tr></thead><tbody>{''.join(rows)}</tbody></table></section>
{''.join(cards)}</main><script>document.querySelectorAll('.compare').forEach(c=>c.querySelector('input').addEventListener('input',e=>c.style.setProperty('--split',e.target.value+'%')))</script></body></html>'''
(root/"index.html").write_text(document)
print(f"Wrote {root/'index.html'}")
