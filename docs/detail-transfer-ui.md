# Detail Transfer UI and engine mapping

## Placement

`Optics` tab → `Detail Transfer` group, after `Focus & Field` and before
`Aberrations`. This is a standard collapsible OFX parameter group and uses only
controls supported by Resolve's native OFX inspector.

The group label deliberately avoids claiming scientific MTF measurement. It is
a perceptual spatial-frequency response intended to reproduce the visible
character of lens transfer behavior.

## Controls

| UI label | OFX type | UI range | Default | Engine member |
|---|---|---:|---:|---|
| Microcontrast | Double slider | -1.000–1.000 | 0.000 | `microContrast` |
| Fine Detail | Double slider | -1.000–1.000 | 0.000 | `fineDetail` |
| Edge Falloff | Double slider | 0.000–1.000 | 0.000 | `detailEdgeFalloff` |
| Sagittal Detail | Double slider | -1.000–1.000 | 0.000 | `sagittalDetail` |
| Tangential Detail | Double slider | -1.000–1.000 | 0.000 | `tangentialDetail` |
| Detail Scale | Double slider | 0.500–4.000 | 1.000 | `detailScale` |

All displayed values use three decimal places. Negative transfer values soften;
positive values increase transfer. `Edge Falloff` is one-sided because it
describes progressive off-axis loss rather than sharpening the edge above the
center response.

## User-facing meaning

- **Microcontrast** changes medium-frequency tonal separation and texture body.
- **Fine Detail** changes fine-frequency acutance without changing geometry.
- **Edge Falloff** progressively lowers fine and medium transfer away from the
  optical center.
- **Sagittal Detail** changes the radial directional response off axis.
- **Tangential Detail** changes the perpendicular directional response off axis.
- **Detail Scale** selects the feature size affected by the other controls.

## Interaction with existing groups

`Focus & Field` continues to describe spatial aberrations: corner softness,
field curvature, astigmatism, and radial/tangential smear. `Detail Transfer`
describes frequency response. They may be combined, but presets should avoid
using both groups heavily unless a deliberately degraded or exotic lens is
intended.

The engine applies halo limiting to Detail Transfer. This does not turn the
controls into conventional digital sharpening; it prevents bright and dark
edge outlines at stronger positive settings.

## Presets and group state

All six values are stored in `.ldbpreset` files. `Detail Scale` is considered
neutral at `1.000`; the other five controls are neutral at `0.000`.

When a preset loads, the `Detail Transfer` group expands if any member is
non-neutral and remains collapsed otherwise. `Clean Slate`/`Reset All` restores
the defaults above. Input Working Space remains excluded from presets.

## Processing and performance behavior

If all five transfer amounts are neutral, the stage is skipped and `Detail
Scale` alone has no effect. The complete neutral plugin retains the engine's
copy bypass. On Apple M1 at 1920×1080, the validated full Detail Transfer case
measured 5.477 ms GPU and 5.860 ms wall time.

## Validation status

- Fine-detail gain and loss: passed
- Independent microcontrast response: passed
- Field-dependent falloff: passed
- Independent sagittal/tangential response: passed
- Detail-scale response: passed
- Alpha preservation: passed
- Step-edge halo suppression: passed
- Polar chart visual response: passed after weighted-band revision
- iPhone DWG/Intermediate real-image response: passed
- Alexa 35 LogC4 with ARRI REVEAL output: passed
