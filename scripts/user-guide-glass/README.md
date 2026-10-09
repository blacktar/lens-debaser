# User guide glass buttons

Approved 2026-10-07: Lens material, Thickness 1.72, Rim 0.39, Rainbow 0.30, Frost 1.70, responsive optical sizing, subtle cyan hover and press feedback. Decorative Ldb remains unchanged.

Based on Amazing Glass by Ivan Tomac, MIT licensed, upstream https://github.com/tomacco/amazing-glass at f238dca414ffaca375df1303eba319f978ce84b1. Retained core sources and unmodified licence in vendor/. Button integration and responsive parameters are local adaptations. No React/Vue runtime is shipped.

Bundle buttons.js with esbuild (bundle, minify, format=esm) to docs/user-guide/glass-buttons.js. buttons.css is included by build-user-guide.py. The upstream stylesheet and licence are distributed alongside the bundle.

Approved update2026-10-08: Thickness1.34, Rim0.16, Rainbow0.30, Frost1.70; original rim highlight1.70 retained. Hover Frost9.0; pressed Rainbow0.15/Frost1.10, .98scale and neutral18%black overlay. No blue interaction tint or parent brightness filter. Ldb untouched.

2026-10-09 portrait correction: natural-size background anchored bottom-right; removed extra mobile darkening. Registered backdrop and Safari CPU refraction now use device-pixel-density backing canvases while optical distances remain CSS pixels. Dispersion is included in the CPU render cache key. Physical iPhone verification remains pending upload.

Safari portrait follow-up: paint the existing Ldb pseudo-element into the registered background canvas and hide its duplicate DOM drawing after readiness. This makes the letters part of the same scene sampled by CPU refraction, preserving computed font, size, colour and placement.

2026-10-09 clarified portrait framing: cover the whole header with aspect-preserving scaling, anchor bottom-right, and crop overflow to the left. CSS and registered glass backdrop use the same cover calculation. This supersedes the natural-size portrait request.

## Rebuild the published guide

Before running `scripts/build-user-guide.py`, bundle the glass script using esbuild and copy its retained stylesheet and licence:

```sh
esbuild scripts/user-guide-glass/buttons.js --bundle --minify --format=esm --outfile=docs/user-guide/glass-buttons.js
cp scripts/user-guide-glass/vendor/styles.css docs/user-guide/amazing-glass.css
cp scripts/user-guide-glass/vendor/LICENSE docs/user-guide/AMAZING-GLASS-LICENSE.txt
python3 scripts/build-user-guide.py
```

Bundle first: the guide generator fingerprints the finished script for its cache-safe URL. Generated guide assets remain outside Git; the retained source and build recipes reproduce them.
