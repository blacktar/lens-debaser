#!/usr/bin/env python3
"""Build the local current-versus-continuous-PSF evaluation page."""

from __future__ import annotations

import html
import hashlib
import re
import sys
from pathlib import Path


TIMING = re.compile(
    r"^(?P<name>\S+)\s+GPU\s+(?P<gpu>[0-9.]+) ms\s+wall\s+(?P<wall>[0-9.]+) ms",
    re.MULTILINE,
)


def timings(text: str) -> dict[str, tuple[float, float]]:
    return {
        match.group("name"): (float(match.group("gpu")), float(match.group("wall")))
        for match in TIMING.finditer(text)
    }


def timing_rows(benchmark: str) -> str:
    values = timings(benchmark)
    rows = []
    for base_name, base in values.items():
        if not base_name.endswith("-base"):
            continue
        case = base_name.removesuffix("-base")
        candidate = values.get(case + "-test")
        if candidate is None:
            continue
        gpu_delta = (candidate[0] / base[0] - 1.0) * 100.0
        wall_delta = (candidate[1] / base[1] - 1.0) * 100.0
        rows.append(
            "<tr>"
            f"<th>{html.escape(case)}</th>"
            f"<td>{base[0]:.3f} ms</td><td>{candidate[0]:.3f} ms</td>"
            f"<td class={'cost' if gpu_delta > 2 else 'gain' if gpu_delta < -2 else 'neutral'}>"
            f"{gpu_delta:+.1f}%</td>"
            f"<td>{base[1]:.3f} ms</td><td>{candidate[1]:.3f} ms</td>"
            f"<td class={'cost' if wall_delta > 2 else 'gain' if wall_delta < -2 else 'neutral'}>"
            f"{wall_delta:+.1f}%</td></tr>"
        )
    return "".join(rows) or '<tr><td colspan="7">Benchmark results are not available.</td></tr>'


def transport_rows(current_path: Path, candidate_path: Path) -> str:
    def read(path: Path) -> dict[str, tuple[float, float, float]]:
        result = {}
        if not path.is_file():
            return result
        for line in path.read_text().splitlines()[1:]:
            fields = line.split("\t")
            if len(fields) == 4:
                result[fields[0]] = tuple(float(value) for value in fields[1:])
        return result
    current, candidate = read(current_path), read(candidate_path)
    rows=[]
    for name, base in current.items():
        test=candidate.get(name)
        if test is None:
            continue
        energy_delta=(test[1]/base[1]-1.0)*100.0 if base[1] else 0.0
        peak_delta=(test[2]/base[2]-1.0)*100.0 if base[2] else 0.0
        rows.append(f"<tr><th>{html.escape(name)}</th><td>{base[1]:.3f}</td>"
                    f"<td>{test[1]:.3f}</td><td>{energy_delta:+.2f}%</td>"
                    f"<td>{base[2]:.3f}</td><td>{test[2]:.3f}</td>"
                    f"<td>{peak_delta:+.2f}%</td></tr>")
    return "".join(rows)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} output-directory", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    current = root / "current"
    candidate = root / "continuous-psf"
    names = sorted(path.name for path in current.glob("*.png"))
    missing = [name for name in names if not (candidate / name).is_file()]
    current_names=set(names)
    candidate_names={path.name for path in candidate.glob("*.png")}
    extra=sorted(candidate_names-current_names)
    if not names or missing or extra:
        print("ERROR: Incomplete field-PSF image pairs.", file=sys.stderr)
        if missing: print("Missing candidate files: "+", ".join(missing),file=sys.stderr)
        if extra: print("Candidate-only files: "+", ".join(extra),file=sys.stderr)
        return 3
    cards = []
    labels = {
        "iso": "ISO 12233 chart",
        "optical": "LDB synthetic optical chart",
        "milano1": "iPhone scene 1",
        "milano2": "iPhone scene 2",
        "milano3": "iPhone scene 3",
    }
    for name in names:
        stem = Path(name).stem
        key = stem.rsplit("-", 1)[-1]
        preset = stem[: -(len(key) + 1)].replace("-", " ")
        title = f"{preset} — {labels.get(key, key)}"
        # The evaluation page is repeatedly rebuilt at the same local URL.
        # Give each side a content-derived URL so WebKit cannot retain images
        # from an earlier run whose filenames happened to be identical.
        current_key = hashlib.sha256((current / name).read_bytes()).hexdigest()[:12]
        candidate_key = hashlib.sha256((candidate / name).read_bytes()).hexdigest()[:12]
        cards.append(f'''<article>
<h2>{html.escape(title)}</h2>
<div class="compare" style="--split:50%">
  <img src="continuous-psf/{html.escape(name)}?v={candidate_key}" alt="Continuous PSF candidate on {html.escape(title)}" loading="lazy" decoding="async">
  <div class="current"><img src="current/{html.escape(name)}?v={current_key}" alt="Current preset output on {html.escape(title)}" loading="lazy" decoding="async"></div>
  <span class="divider" aria-hidden="true"></span>
  <span class="label left">Current preset output</span><span class="label right">Continuous PSF candidate</span>
  <input type="range" min="0" max="100" value="50" aria-label="Compare current and continuous PSF output for {html.escape(title)}">
</div></article>''')
    benchmark_path = root / "benchmark.txt"
    benchmark = benchmark_path.read_text(errors="replace") if benchmark_path.is_file() else ""
    transport=transport_rows(current/"light-transport-metrics.tsv",
                             candidate/"light-transport-metrics.tsv")
    transport_section=(f'''<section class="benchmark"><h2>Controlled light-transport measurements</h2><p>Integrated scene-linear AP1 luminance and peak luminance from identical point-highlight fixtures. These figures expose lost energy, unintended amplification and threshold changes; they are diagnostic measurements rather than a requirement that additive creative scatter conserve energy.</p><table><thead><tr><th>Case</th><th>Current energy</th><th>Candidate energy</th><th>Energy change</th><th>Current peak</th><th>Candidate peak</th><th>Peak change</th></tr></thead><tbody>{transport}</tbody></table></section>''' if transport else "")
    document = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lens Debaser — Continuous PSF Evaluation</title>
<style>
:root{{--paper:#101315;--card:#1a1e21;--line:#394047;--ink:#edf1f3;--muted:#aab2b8;--accent:#16cbf6}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}
header,main{{width:min(1500px,94vw);margin:auto}}header{{padding:55px 0 25px}}h1{{font-size:clamp(2rem,5vw,4.8rem);line-height:.96;margin:.15em 0}}header p{{max-width:850px;color:var(--muted)}}article,.benchmark{{margin:28px 0;padding:18px;background:var(--card);border:1px solid var(--line)}}h2{{font-size:1rem;margin:0 0 12px;color:var(--accent);text-transform:uppercase;letter-spacing:.08em}}
.compare{{position:relative;overflow:hidden;background:#050607;line-height:0;touch-action:none}}.compare>img,.current img{{display:block;width:100%;height:auto}}.current{{position:absolute;inset:0;clip-path:inset(0 calc(100% - var(--split)) 0 0)}}.divider{{position:absolute;top:0;bottom:0;left:var(--split);width:2px;background:#fff;box-shadow:0 0 0 1px #0008}}.label{{position:absolute;top:12px;padding:5px 8px;background:#080a0bd9;color:white;font-size:12px;line-height:1.2}}.left{{left:12px}}.right{{right:12px}}.compare input{{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:ew-resize}}
table{{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}}th,td{{padding:9px;border-bottom:1px solid var(--line);text-align:right}}th:first-child{{text-align:left}}thead th{{color:var(--muted);font-size:12px}}.cost{{color:#ff9b87}}.gain{{color:#8ce7a1}}.neutral{{color:var(--muted)}}code{{color:var(--accent)}}
</style></head><body><header><p>EXPERIMENTAL ESCALATION LAYER 1</p><h1>Continuous PSF<br>preset evaluation</h1><p>Swipe each image to compare the currently passed preset output with a candidate that grows the optical point-spread function continuously instead of crossfading a registered sharp image with a completed blur. Neither candidate code nor these images are release assets.</p></header><main>
{''.join(cards)}
{transport_section}
<section class="benchmark"><h2>Performance comparison</h2><table><thead><tr><th>Case</th><th>Current GPU</th><th>Candidate GPU</th><th>GPU change</th><th>Current wall</th><th>Candidate wall</th><th>Wall change</th></tr></thead><tbody>{timing_rows(benchmark)}</tbody></table></section>
</main><script>document.querySelectorAll('.compare').forEach(box=>{{const input=box.querySelector('input'),layer=box.querySelector('.current'),divider=box.querySelector('.divider');const update=()=>{{const value=Number(input.value);layer.style.clipPath=`inset(0 ${{100-value}}% 0 0)`;divider.style.left=value+'%';}};input.addEventListener('input',update);update();}});</script></body></html>'''
    (root / "index.html").write_text(document)
    print(f"Built {root / 'index.html'} with {len(names)} visual comparisons.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
