#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
release_version=${1:-1.67}
release_zip="$repo_root/releases/Lens-Debaser-${release_version}-Apple-Silicon.zip"
work_root="$repo_root/build/experiments/released-${release_version}-baseline"
extract_root="$work_root/archive"
release_root="$extract_root/Lens-Debaser-${release_version}-Apple-Silicon"
baseline_library="$release_root/LensDebaser.ofx.bundle/Contents/Resources/LDBOptics.metallib"
output_root="$repo_root/outputs/experiments/full-preset-release-comparison"
baseline_output="$output_root/released-${release_version}"
candidate_output="$output_root/continuous-psf-candidate"

cd "$repo_root"
if [[ ! -d "$baseline_output" || ! -d "$candidate_output" ]]; then
  print -u2 "ERROR: Run make full-preset-release-comparison first."
  exit 2
fi
if [[ ! -f "$baseline_library" ]]; then
  [[ -f "$release_zip" ]] || { print -u2 "ERROR: Missing release archive: $release_zip"; exit 3; }
  rm -rf "$extract_root"
  mkdir -p "$extract_root"
  /usr/bin/unzip -q "$release_zip" -d "$extract_root"
fi

make build/experiments/LDBOptics-field-psf.metallib build/ldb-guide-examples
build/ldb-guide-examples "$baseline_library" "$repo_root" \
  "$baseline_output" light-transport-validation
build/ldb-guide-examples build/experiments/LDBOptics-field-psf.metallib \
  "$repo_root" "$candidate_output" light-transport-validation

[[ -L "$output_root/current" ]] || ln -s "released-${release_version}" "$output_root/current"
[[ -L "$output_root/continuous-psf" ]] || ln -s continuous-psf-candidate "$output_root/continuous-psf"
./scripts/build-field-psf-report.py "$output_root"
print "Updated audit: $output_root/index.html"
