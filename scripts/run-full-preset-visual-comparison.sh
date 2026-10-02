#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
release_version=${1:-1.67}
release_zip="$repo_root/releases/Lens-Debaser-${release_version}-Apple-Silicon.zip"
work_root="$repo_root/build/experiments/released-${release_version}-baseline"
extract_root="$work_root/archive"
baseline_presets="$work_root/presets"
output_root="$repo_root/outputs/experiments/full-preset-release-comparison-clean"

if [[ ! -f "$release_zip" ]]; then
  print -u2 "ERROR: Released baseline archive not found: $release_zip"
  exit 2
fi

cd "$repo_root"

# This is a clean-room comparison. Never reuse an experimental AIR/metallib:
# the compiler define is the identity of the candidate being evaluated.
rm -f build/experiments/LDBOptics-field-psf.air \
      build/experiments/LDBOptics-field-psf.metallib
make build/experiments/LDBOptics-field-psf.metallib build/ldb-guide-examples build/ldb-optics-benchmark

# These are narrowly scoped generated folders. Removing them prevents stale
# images from a previous comparison from appearing as valid current results.
rm -rf "$work_root" "$output_root"
mkdir -p "$extract_root" "$baseline_presets/demonstrations" \
         "$baseline_presets/cinematic-lenses" "$output_root/released-${release_version}" \
         "$output_root/continuous-psf-candidate"
/usr/bin/unzip -q "$release_zip" -d "$extract_root"

release_root="$extract_root/Lens-Debaser-${release_version}-Apple-Silicon"
baseline_library="$release_root/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib"
if [[ ! -f "$baseline_library" ]]; then
  print -u2 "ERROR: Released Metal library is missing from the archive."
  exit 3
fi
cp "$release_root/Presets/Demonstrations/"*.ldbpreset "$baseline_presets/demonstrations/"
cp "$release_root/Presets/Cinematic Lenses/"*.ldbpreset "$baseline_presets/cinematic-lenses/"

baseline_count=$(find "$baseline_presets" -type f -name '*.ldbpreset' | wc -l | tr -d ' ')
candidate_count=$(find presets/demonstrations presets/cinematic-lenses -type f -name '*.ldbpreset' | wc -l | tr -d ' ')
if [[ "$baseline_count" != "$candidate_count" ]]; then
  print -u2 "ERROR: Baseline has $baseline_count presets but candidate has $candidate_count."
  exit 4
fi

LDB_PRESET_ROOT="$baseline_presets" build/ldb-guide-examples \
  "$baseline_library" "$repo_root" "$output_root/released-${release_version}" \
  all-preset-library-validation
LDB_PRESET_ROOT="$repo_root/presets" \
build/ldb-guide-examples build/experiments/LDBOptics-field-psf.metallib \
  "$repo_root" "$output_root/continuous-psf-candidate" \
  all-preset-library-validation

# Append controlled point-highlight cases and scene-linear energy measurements
# to both sides before the shared HTML report is assembled.
build/ldb-guide-examples "$baseline_library" "$repo_root" \
  "$output_root/released-${release_version}" light-transport-validation
build/ldb-guide-examples build/experiments/LDBOptics-field-psf.metallib \
  "$repo_root" "$output_root/continuous-psf-candidate" light-transport-validation

build/ldb-optics-benchmark "$baseline_library" \
  build/experiments/LDBOptics-field-psf.metallib | tee "$output_root/benchmark.txt"

# Record exact inputs. This makes it possible to prove which engine and preset
# collection produced either side without trusting directory names or labels.
{
  print "side\tmetallib_sha256\tpreset_tree_sha256"
  baseline_lib_hash=$(/usr/bin/shasum -a 256 "$baseline_library" | awk '{print $1}')
  candidate_lib_hash=$(/usr/bin/shasum -a 256 build/experiments/LDBOptics-field-psf.metallib | awk '{print $1}')
  baseline_preset_hash=$(find "$baseline_presets" -type f -name '*.ldbpreset' | sort | xargs /usr/bin/shasum -a 256 | /usr/bin/shasum -a 256 | awk '{print $1}')
  candidate_preset_hash=$(find presets/demonstrations presets/cinematic-lenses -type f -name '*.ldbpreset' | sort | xargs /usr/bin/shasum -a 256 | /usr/bin/shasum -a 256 | awk '{print $1}')
  print "released-${release_version}\t${baseline_lib_hash}\t${baseline_preset_hash}"
  print "continuous-psf-candidate\t${candidate_lib_hash}\t${candidate_preset_hash}"
} > "$output_root/provenance.tsv"

if [[ "$baseline_lib_hash" == "$candidate_lib_hash" ]]; then
  print -u2 "ERROR: Candidate and released metallibs are identical."
  exit 5
fi

# A field-heavy preset must differ. Abort instead of publishing a second
# baseline under a candidate label.
sentinel="cinematic-26-internal-field-edge-fx-iso.png"
if [[ ! -f "$output_root/released-${release_version}/$sentinel" || \
      ! -f "$output_root/continuous-psf-candidate/$sentinel" ]]; then
  print -u2 "ERROR: Required candidate sentinel was not rendered: $sentinel"
  exit 6
fi
if cmp -s "$output_root/released-${release_version}/$sentinel" \
          "$output_root/continuous-psf-candidate/$sentinel"; then
  print -u2 "ERROR: Candidate sentinel is byte-identical to the released baseline."
  exit 7
fi

# The report builder expects stable relative side names.
ln -s "released-${release_version}" "$output_root/current"
ln -s continuous-psf-candidate "$output_root/continuous-psf"
./scripts/build-field-psf-report.py "$output_root"

print ""
print "Full released-${release_version} comparison:"
print "$output_root/index.html"
