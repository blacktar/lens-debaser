#!/usr/bin/env python3
"""Build the focused Optical Drift preset review page."""

from pathlib import Path
import html
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} output-directory", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    sources = {
        "iso": "ISO 12233 chart",
        "optical": "LDB synthetic optical chart",
        "milano1": "iPhone scene 1",
        "milano2": "iPhone scene 2",
        "milano3": "iPhone scene 3",
    }
    presets = {
        "demo-32-optical-drift": "Demo 32 — Optical Drift",
        "cinematic-27-decentered-drift-prime": "27 — Decentered Drift Prime",
        "cinematic-28-spectral-radial-drift": "28 — Spectral Radial Drift",
    }
    cards = []
    for preset, preset_label in presets.items():
        for source, source_label in sources.items():
            before = root / f"before-{source}.png"
            after = root / f"{preset}-{source}.png"
            if not before.is_file() or not after.is_file():
                print(f"ERROR: Missing comparison pair for {preset} / {source}", file=sys.stderr)
                return 3
            cards.append(f'''<article><h2>{html.escape(preset_label)} · {html.escape(source_label)}</h2>
<div class="compare" style="--split:50%">
  <img src="{html.escape(after.name)}" alt="{html.escape(preset_label)} applied" loading="lazy" decoding="async">
  <div class="before"><img src="{html.escape(before.name)}" alt="Clean source" loading="lazy" decoding="async"></div>
  <span class="divider"></span><span class="label left">Clean source</span><span class="label right">{html.escape(preset_label)}</span>
  <input type="range" min="0" max="100" value="50" aria-label="Compare {html.escape(preset_label)} on {html.escape(source_label)}">
</div></article>''')
            if preset == "demo-32-optical-drift":
                drift_off = root / f"{preset}-drift-off-{source}.png"
                if not drift_off.is_file():
                    print(f"ERROR: Missing Drift-off comparison for {source}", file=sys.stderr)
                    return 3
                cards.append(f'''<article><h2>Demo 32 contribution · {html.escape(source_label)}</h2>
<div class="compare" style="--split:50%">
  <img src="{html.escape(after.name)}" alt="Optical Drift enabled" loading="lazy" decoding="async">
  <div class="before"><img src="{html.escape(drift_off.name)}" alt="Same aperture treatment with Optical Drift disabled" loading="lazy" decoding="async"></div>
  <span class="divider"></span><span class="label left">Drift off · same aperture</span><span class="label right">Drift on · Amount 0.64</span>
  <input type="range" min="0" max="100" value="50" aria-label="Isolate Optical Drift contribution on {html.escape(source_label)}">
</div></article>''')
    document = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lens Debaser — Optical Drift Preset Review</title><style>
:root{{--paper:#0a0c0e;--card:#15191d;--line:#303840;--ink:#f2f5f6;--muted:#aab3ba;--accent:#16cbf6}}*{{box-sizing:border-box}}
body{{margin:0;background:var(--paper);color:var(--ink);font:16px/1.5 system-ui,-apple-system,sans-serif}}header,main{{width:min(1600px,96vw);margin:auto}}header{{padding:48px 0 20px}}h1{{font-size:clamp(2rem,5vw,4.5rem);line-height:1;margin:0 0 12px}}header p{{max-width:80ch;color:var(--muted)}}article{{margin:28px 0;padding:18px;background:var(--card);border:1px solid var(--line);border-radius:12px}}h2{{font-size:1rem;margin:0 0 12px;color:var(--accent)}}
.compare{{position:relative;overflow:hidden;background:#000;line-height:0;touch-action:none}}.compare>img,.before img{{display:block;width:100%;height:auto}}.before{{position:absolute;inset:0;clip-path:inset(0 calc(100% - var(--split)) 0 0)}}.divider{{position:absolute;top:0;bottom:0;left:var(--split);width:2px;background:#fff;box-shadow:0 0 0 1px #0008}}.label{{position:absolute;top:12px;padding:6px 9px;background:#07090bda;color:#fff;font-size:12px;line-height:1.2}}.left{{left:12px}}.right{{right:12px;color:var(--accent)}}.compare input{{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:ew-resize}}
</style></head><body><header><h1>Optical Drift preset review</h1><p>Focused candidate review. Demo 32 isolates a restrained radial drift response. Decentered Drift Prime is the usable compound treatment; Spectral Radial Drift is the stronger demonstration treatment. These are not approved release assets until visually signed off.</p></header><main>{''.join(cards)}</main>
<script>document.querySelectorAll('.compare').forEach(box=>{{const input=box.querySelector('input'),layer=box.querySelector('.before'),line=box.querySelector('.divider');const update=()=>{{const v=Number(input.value);layer.style.clipPath=`inset(0 ${{100-v}}% 0 0)`;line.style.left=v+'%'}};input.addEventListener('input',update);update()}})</script></body></html>'''
    (root / "index.html").write_text(document)
    print(f"Built {root / 'index.html'} with {len(cards)} comparisons.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
