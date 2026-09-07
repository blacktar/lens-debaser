# Validation reference images

These files are the repository-local source images used by `make visual-test`
and `make deploy`:

- `ISO_12233-reschart.tif` — resolution and spatial-optics chart;
- `iphone_milano_dwg_1.tif` — iPhone frame encoded as DaVinci Wide
  Gamut/Intermediate;
- `arri_log00086400.tif` — ARRI ALEXA 35 frame encoded as ARRI LogC4.

They are source references, not expected display-referred images. The visual
validation program performs its configured working-space conversion and display
rendering after applying the optical model.

SHA-256 checksums:

```text
791d9c26510557a4facdaa2fa857c7a6ffc761574b804cf373be98acdbc76305  ISO_12233-reschart.tif
29d2f787ecaa4e918e06e49ebf24a8157b8eebf925e71cb3ba07b010ca258d4b  iphone_milano_dwg_1.tif
70aca778367734ec3ffaefbcec30d2ef4d46f2a09f29a231ac6259656c0d7e0e  arri_log00086400.tif
```

The project owner has confirmed that supplied imagery is owned or licensed for
inclusion in this project. These files are distributed under the repository's
CC BY-NC-SA 4.0 license unless a file-specific notice states otherwise.
