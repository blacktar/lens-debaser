# Resolve builds require full Xcode. Do not depend on the global xcode-select
# setting, which macOS/Command Line Tools updates can change underneath us.
XCODE_DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
XCRUN := env DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcrun
SDKROOT := $(shell $(XCRUN) --sdk macosx --show-sdk-path)
MOBILE_METAL_BIN := $(dir $(firstword $(wildcard /private/var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-*/Metal.xctoolchain/usr/bin/metal)))
METAL := $(if $(MOBILE_METAL_BIN),$(MOBILE_METAL_BIN)metal,$(shell $(XCRUN) --find metal 2>/dev/null))
METALLIB := $(if $(MOBILE_METAL_BIN),$(MOBILE_METAL_BIN)metallib,$(shell $(XCRUN) --find metallib 2>/dev/null))
CXX := $(XCRUN) clang++
BUILD := build
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/$(BUILD)/module-cache
METAL_AIR := $(BUILD)/LDBOptics.air
METAL_LIB := $(BUILD)/LDBOptics.metallib
TEST_BIN := $(BUILD)/ldb-optics-tests
VISUAL_BIN := $(BUILD)/ldb-optics-visual-validation
BENCHMARK_BIN := $(BUILD)/ldb-optics-benchmark
APERTURE_CHART_BIN := $(BUILD)/ldb-aperture-chart
SYNTHETIC_OPTICAL_CHART_BIN := $(BUILD)/ldb-synthetic-optical-chart
GUIDE_EXAMPLES_BIN := $(BUILD)/ldb-guide-examples
FIELD_PSF_AIR := $(BUILD)/experiments/LDBOptics-field-psf.air
FIELD_PSF_LIB := $(BUILD)/experiments/LDBOptics-field-psf.metallib
GUIDE_EXAMPLES_DIR := docs/user-guide/images/examples
APERTURE_CHART := outputs/aperture-pupil-test-acescg-linear.tiff
SYNTHETIC_OPTICAL_CHART := inputs/redistributable/LDB-Synthetic-Optical-Chart.png
RESOLVE_OFX := /Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/OpenFX
OFX_INCLUDE := $(RESOLVE_OFX)/OpenFX-1.4/include
OFX_SUPPORT_INCLUDE := $(RESOLVE_OFX)/Support/include
OFX_SUPPORT_LIBRARY := $(RESOLVE_OFX)/Support/Library
OFX_BUILD := $(BUILD)/ofx
OFX_BUNDLE := $(BUILD)/LensDebaser.ofx.bundle
OFX_BINARY := $(OFX_BUNDLE)/Contents/MacOS/LensDebaser.ofx
PRODUCT_LABEL := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleName' resources/Info.plist 2>/dev/null)
PRODUCT_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' resources/Info.plist 2>/dev/null)
PRODUCT_BUILD := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' resources/Info.plist 2>/dev/null)
OFX_SUPPORT_SOURCES := ofxsCore ofxsImageEffect ofxsInteract ofxsLog ofxsMultiThread ofxsParams ofxsProperty ofxsPropertyValidation
OFX_SUPPORT_OBJECTS := $(addprefix $(OFX_BUILD)/,$(addsuffix .o,$(OFX_SUPPORT_SOURCES)))
REFERENCE_DIR ?= $(CURDIR)/references
ISO_CHART ?= $(REFERENCE_DIR)/ISO_12233-reschart.tif
REAL_FOOTAGE ?= $(REFERENCE_DIR)/iphone_milano_dwg_1.tif
ARRI_FOOTAGE ?= $(REFERENCE_DIR)/arri_log00086400.tif
HAWK_REFERENCE ?= $(CURDIR)/inputs/Reference_Lenses/Hawk V-Lite Vintage `74 Anamorphic/Hawk_TIFFs/Hawk V-Lite Vintage `74 Anamorphic 55mm T2.2 at T2.2_log.tif
COOKE_SPECIAL_REFERENCE ?= $(CURDIR)/inputs/Reference_Lenses/Cooke Anamorphic :i Special Flare/CookeSpecial_TIFFs/Cooke Anamorphic i Special Flare 50mm T2.3 at T2.3_log.tif
ARRI_REVEAL_LUT ?= /Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT/Arri/ARRI_LogC4_v1_LUT_Package/LUTs/ARRI_LogC4-to-Gamma24_Rec709-D65_v1-65.cube
VALIDATION_ROOT := outputs/engine-validation
VISUAL_PASS_ID := 100
VISUAL_PASS_LABEL := Visual Pass $(VISUAL_PASS_ID) - Continuous Field and Aperture PSF
VALIDATION_OUTPUT := $(VALIDATION_ROOT)/passes/pass-$(VISUAL_PASS_ID)

.PHONY: all ofx validate version-check performance-test deploy release aperture-chart synthetic-optical-chart guide-examples guide-examples-glare guide-examples-presets-166 guide-examples-presets-166b guide-examples-presets-167 guide-examples-preset-26 optical-model-validation optical-model-benchmark field-psf-experiment field-psf-library-experiment light-transport-audit full-preset-release-comparison full-library-validation user-guide guide-update guide-update-status guide-publish-record presets preset-test preset-schema preset-authoring-kit validate-user-preset install install-user test visual-test visual-check visual-rebuild clean

all: $(METAL_LIB) $(TEST_BIN) $(VISUAL_BIN) $(BENCHMARK_BIN)

ofx: $(OFX_BINARY)

install: install-user

release: validate preset-authoring-kit ofx
	./scripts/package-release.sh

# Deployment validation is a correctness and visual-output gate. Keep the
# sustained benchmark explicit: it is sensitive to machine load and thermal
# state, and is required when processing changes rather than for every install.
validate: version-check preset-test test visual-check

version-check:
	@grep -Fq 'constexpr const char *kName = "$(PRODUCT_LABEL)";' src/ofx/LensDebaserPlugin.cpp || { echo "ERROR: OFX display name does not match $(PRODUCT_LABEL)." >&2; exit 1; }
	@grep -Fq 'Current development version: **$(PRODUCT_VERSION)**.' README.md || { echo "ERROR: README version does not match $(PRODUCT_VERSION)." >&2; exit 1; }
	@grep -Fq 'CURRENT_PRESET_TAG = "v$(PRODUCT_VERSION)"' scripts/generate-presets.py || { echo "ERROR: test-preset version does not match $(PRODUCT_VERSION)." >&2; exit 1; }

performance-test: benchmark

presets:
	./scripts/generate-presets.py

preset-test: presets
	@test "$$(find presets/demonstrations presets/cinematic-lenses -name '*.ldbpreset' -type f | wc -l | tr -d ' ')" = 104 || { echo "ERROR: Expected 104 generated factory presets." >&2; exit 1; }
	@! grep -REn '^(inputWorkingSpace|diagnosticView|depthSource)=' presets/demonstrations presets/cinematic-lenses || { echo "ERROR: A processing-only or removed control was serialized in a factory preset." >&2; exit 1; }

preset-schema:
	./scripts/build-preset-schema.py

preset-authoring-kit: preset-schema
	./scripts/validate-preset.py preset-authoring/Clean-Slate-Template.ldbpreset preset-authoring/examples/*.ldbpreset

validate-user-preset: preset-schema
	@test -n "$(PRESET)" || { echo "ERROR: Supply PRESET=/absolute/path/My-Lens.ldbpreset" >&2; exit 1; }
	./scripts/validate-preset.py "$(PRESET)"

# One command for a Resolve test build: validate the engine and visual outputs,
# then install only if every preceding step succeeds.
deploy:
	@if pgrep -x "Resolve" >/dev/null; then echo "ERROR: Fully quit DaVinci Resolve before deployment." >&2; exit 1; fi
	@test -d "$(XCODE_DEVELOPER_DIR)" || { echo "ERROR: Full Xcode is required at $(XCODE_DEVELOPER_DIR)." >&2; exit 1; }
	@test -d "$(OFX_INCLUDE)" || { echo "ERROR: Resolve OpenFX SDK is unavailable at $(OFX_INCLUDE)." >&2; exit 1; }
	@test -x "$(METAL)" && test -x "$(METALLIB)" || { echo "ERROR: Apple Metal compiler tools are unavailable." >&2; exit 1; }
	@for reference in "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" "$(ARRI_REVEAL_LUT)" '$(HAWK_REFERENCE)' '$(COOKE_SPECIAL_REFERENCE)'; do test -f "$$reference" || { echo "ERROR: Required validation reference is missing: $$reference" >&2; exit 1; }; done
	$(MAKE) validate
	@printf '\nInspect $(VALIDATION_OUTPUT), especially newly changed optical renders.\nInstall $(PRODUCT_LABEL) (build $(PRODUCT_BUILD)) into Resolve? [y/N] '; \
		read answer; case "$$answer" in y|Y|yes|YES) $(MAKE) install-user ;; *) echo "Validation completed; installation skipped." ;; esac

install-user:
	./scripts/install-user.sh

$(OFX_BUILD):
	mkdir -p $(OFX_BUILD)

$(OFX_BUILD)/LensDebaserPlugin.o: src/ofx/LensDebaserPlugin.cpp src/ofx/LensDebaserPlugin.h src/ofx/LensDebaserMetal.h include/LDBOpticsParameters.h | $(OFX_BUILD)
	$(CXX) -std=c++20 -arch arm64 -fvisibility=hidden -Iinclude -Isrc/ofx -I"$(OFX_INCLUDE)" -I"$(OFX_SUPPORT_INCLUDE)" -c $< -o $@

$(OFX_BUILD)/LensDebaserMetal.o: src/ofx/LensDebaserMetal.mm src/ofx/LensDebaserMetal.h src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h | $(OFX_BUILD)
	$(CXX) -std=c++20 -arch arm64 -fvisibility=hidden -Iinclude -Isrc/ofx -c $< -o $@

$(OFX_BUILD)/LDBOpticsEngine.o: src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h | $(OFX_BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -fvisibility=hidden -Iinclude -c $< -o $@

$(OFX_SUPPORT_OBJECTS): | $(OFX_BUILD)
	$(CXX) -std=c++20 -arch arm64 -fvisibility=hidden -I"$(OFX_INCLUDE)" -I"$(OFX_SUPPORT_INCLUDE)" -c "$(OFX_SUPPORT_LIBRARY)/$(notdir $(basename $@)).cpp" -o $@

$(OFX_BINARY): $(OFX_BUILD)/LensDebaserPlugin.o $(OFX_BUILD)/LensDebaserMetal.o $(OFX_BUILD)/LDBOpticsEngine.o $(OFX_SUPPORT_OBJECTS) $(METAL_LIB) resources/ldb.png resources/Info.plist
	mkdir -p "$(OFX_BUNDLE)/Contents/MacOS" "$(OFX_BUNDLE)/Contents/Resources"
	$(CXX) -arch arm64 -bundle -fvisibility=hidden $(OFX_BUILD)/LensDebaserPlugin.o $(OFX_BUILD)/LensDebaserMetal.o $(OFX_BUILD)/LDBOpticsEngine.o $(OFX_SUPPORT_OBJECTS) -o "$@" -framework Foundation -framework Metal -framework AppKit
	cp $(METAL_LIB) "$(OFX_BUNDLE)/Contents/Resources/LDBOptics.metallib"
	rm -f "$(OFX_BUNDLE)/Contents/Resources/ldb.png"
	sips -z 256 256 resources/ldb.png --out "$(OFX_BUNDLE)/Contents/Resources/com.ldb.LensDebaser.png" >/dev/null
	cp resources/Info.plist "$(OFX_BUNDLE)/Contents/Info.plist"
	xattr -cr "$(OFX_BUNDLE)"
	xattr -d com.apple.FinderInfo "$(OFX_BUNDLE)" 2>/dev/null || true
	xattr -d 'com.apple.fileprovider.fpfs#P' "$(OFX_BUNDLE)" 2>/dev/null || true

$(BUILD):
	mkdir -p $(BUILD)/module-cache

$(METAL_AIR): src/metal/LDBOptics.metal include/LDBOpticsParameters.h | $(BUILD)
	$(METAL) -c $< -o $@ -std=metal3.1 -Iinclude -isysroot $(SDKROOT) -fmodules-cache-path=$(CURDIR)/$(BUILD)/module-cache

$(METAL_LIB): $(METAL_AIR)
	$(METALLIB) $< -o $@

$(FIELD_PSF_AIR): src/metal/LDBOptics.metal include/LDBOpticsParameters.h | $(BUILD)
	mkdir -p $(BUILD)/experiments
	$(METAL) -c $< -o $@ -std=metal3.1 -DLDB_EXPERIMENT_CONTINUOUS_FIELD_PSF=1 -Iinclude -isysroot $(SDKROOT) -fmodules-cache-path=$(CURDIR)/$(BUILD)/module-cache

$(FIELD_PSF_LIB): $(FIELD_PSF_AIR)
	$(METALLIB) $< -o $@

$(TEST_BIN): tests/MetalEngineTests.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h include/LDBColorReference.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/MetalEngineTests.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal

$(VISUAL_BIN): tests/VisualValidation.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h include/LDBColorReference.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/VisualValidation.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal -framework CoreGraphics -framework ImageIO

$(GUIDE_EXAMPLES_BIN): tests/GuideExamples.mm tests/VisualValidation.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h include/LDBColorReference.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude -Itests tests/GuideExamples.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal -framework CoreGraphics -framework ImageIO

guide-examples: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART) presets
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required guide source is missing: $$reference" >&2; exit 1; }; done
	rm -rf "$(GUIDE_EXAMPLES_DIR)"
	mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)"
	./scripts/build-user-guide.py

# Refresh only examples whose rendered appearance depends on the independent
# glare threshold/model. Existing reviewed examples remain byte-for-byte intact.
guide-examples-glare: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART)
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required guide source is missing: $$reference" >&2; exit 1; }; done
	@mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)" changed-glare
	./scripts/build-user-guide.py

# Refresh only the demonstration and cinematic examples revised after the
# 1.65 optical-model review. All previously reviewed images remain untouched.
guide-examples-presets-166: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART) presets
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required guide source is missing: $$reference" >&2; exit 1; }; done
	@mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)" changed-presets-166
	rm -f "$(GUIDE_EXAMPLES_DIR)"/blend-iso-100.png "$(GUIDE_EXAMPLES_DIR)"/blend-iso-50.png
	./scripts/build-user-guide.py

# Second focused review: only presets adjusted after the first 1.66 render.
guide-examples-presets-166b: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART) presets
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required guide source is missing: $$reference" >&2; exit 1; }; done
	@mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)" changed-presets-166b
	./scripts/build-user-guide.py

# 1.67 changes only Demo 25's rendered guide appearance. Preserve every
# previously reviewed guide image byte-for-byte and replace these five files.
guide-examples-presets-167: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART) presets
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required validation source is missing: $$reference" >&2; exit 1; }; done
	@mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)" changed-presets-167
	./scripts/build-user-guide.py

# Render only the five atlas images for the reviewed Internal Field Edge FX
# signature preset. Existing reviewed examples remain byte-for-byte intact.
guide-examples-preset-26: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART) presets
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required validation source is missing: $$reference" >&2; exit 1; }; done
	@mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)" changed-preset-26
	./scripts/build-user-guide.py

# Focused review material for the promoted field-blur and chromatic-ordering
# model. This does not touch guide images, visual-pass archives, or presets.
optical-model-validation: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN)
	@for reference in inputs/redistributable/ISO_12233-reschart.tif inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required validation source is missing: $$reference" >&2; exit 1; }; done
	rm -rf outputs/experiments/optical-model-candidate
	mkdir -p outputs/experiments/optical-model-candidate
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" outputs/experiments/optical-model-candidate optical-model-validation
	@printf '\nFocused renders: outputs/experiments/optical-model-candidate\n'

# Save the absolute production timings beside the focused review renders.
# This target does not regenerate any imagery.
optical-model-benchmark: $(METAL_LIB) $(BENCHMARK_BIN)
	@mkdir -p outputs/experiments/optical-model-candidate
	$(BENCHMARK_BIN) $(METAL_LIB) | tee outputs/experiments/optical-model-candidate/benchmark.txt

# Escalation layer 1: compare the passed registered sharp/blur composite with
# a continuously growing field PSF. This never replaces the shipping metallib,
# presets, guide images, visual archives, or release bundle.
field-psf-experiment: $(METAL_LIB) $(FIELD_PSF_LIB) $(GUIDE_EXAMPLES_BIN) $(BENCHMARK_BIN)
	@for reference in inputs/redistributable/ISO_12233-reschart.tif inputs/redistributable/LDB-Synthetic-Optical-Chart.png inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required validation source is missing: $$reference" >&2; exit 1; }; done
	rm -rf outputs/experiments/field-psf-layer-1
	mkdir -p outputs/experiments/field-psf-layer-1/current outputs/experiments/field-psf-layer-1/continuous-psf
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" outputs/experiments/field-psf-layer-1/current field-psf-validation
	$(GUIDE_EXAMPLES_BIN) $(FIELD_PSF_LIB) "$(CURDIR)" outputs/experiments/field-psf-layer-1/continuous-psf field-psf-validation
	$(BENCHMARK_BIN) $(METAL_LIB) $(FIELD_PSF_LIB) | tee outputs/experiments/field-psf-layer-1/benchmark.txt
	./scripts/build-field-psf-report.py outputs/experiments/field-psf-layer-1
	@printf '\nExperimental comparison: outputs/experiments/field-psf-layer-1/index.html\n'

# Expanded review after the focused Internal Field Edge FX candidate passes its
# first inspection. Select only factory presets that activate field blur or the
# aperture reconstruction, but render every available strength and all five
# validation sources. Release and guide assets remain untouched.
field-psf-library-experiment: $(METAL_LIB) $(FIELD_PSF_LIB) $(GUIDE_EXAMPLES_BIN) $(BENCHMARK_BIN)
	@for reference in inputs/redistributable/ISO_12233-reschart.tif inputs/redistributable/LDB-Synthetic-Optical-Chart.png inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required validation source is missing: $$reference" >&2; exit 1; }; done
	rm -rf outputs/experiments/field-psf-library
	mkdir -p outputs/experiments/field-psf-library/current outputs/experiments/field-psf-library/continuous-psf
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" outputs/experiments/field-psf-library/current field-psf-library-validation
	$(GUIDE_EXAMPLES_BIN) $(FIELD_PSF_LIB) "$(CURDIR)" outputs/experiments/field-psf-library/continuous-psf field-psf-library-validation
	$(BENCHMARK_BIN) $(METAL_LIB) $(FIELD_PSF_LIB) | tee outputs/experiments/field-psf-library/benchmark.txt
	./scripts/build-field-psf-report.py outputs/experiments/field-psf-library
	@printf '\nFull relevant-preset comparison: outputs/experiments/field-psf-library/index.html\n'

# One-command audit of every factory preset against an immutable packaged
# release. Pass BASELINE_VERSION=x.y to select another retained release.
full-preset-release-comparison:
	./scripts/run-full-preset-visual-comparison.sh "$(or $(BASELINE_VERSION),1.67)"

# Append or refresh only the controlled highlight fixtures and rebuild the
# existing report. It deliberately preserves all completed preset renders.
light-transport-audit:
	./scripts/run-light-transport-audit.sh "$(or $(BASELINE_VERSION),1.67)"

# Render the complete current demonstration and cinematic-preset library into
# an isolated candidate folder. Existing guide images remain untouched until
# the candidate has been reviewed and explicitly accepted.
full-library-validation: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) $(SYNTHETIC_OPTICAL_CHART)
	@for reference in inputs/redistributable/ISO_12233-reschart.tif $(SYNTHETIC_OPTICAL_CHART) inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required validation source is missing: $$reference" >&2; exit 1; }; done
	rm -rf outputs/experiments/full-library-candidate
	mkdir -p outputs/experiments/full-library-candidate
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" outputs/experiments/full-library-candidate
	@printf '\nFull-library candidate: outputs/experiments/full-library-candidate\n'

user-guide:
	./scripts/build-user-guide.py

# The public guide is hosted outside the release archive. This bundle contains
# only files that differ from the last explicitly confirmed manual upload.
guide-update:
	./scripts/package-guide-update.py bundle

guide-update-status:
	./scripts/package-guide-update.py status

# Run only after the incremental bundle has been uploaded and checked online.
guide-publish-record:
	./scripts/package-guide-update.py record

$(BENCHMARK_BIN): tests/MetalBenchmark.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/MetalBenchmark.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal

$(APERTURE_CHART_BIN): tests/ApertureChartGenerator.cpp | $(BUILD)
	$(CXX) -std=c++20 -arch arm64 $< -o $@

$(SYNTHETIC_OPTICAL_CHART_BIN): tests/SyntheticOpticalChartGenerator.mm | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 $< -o $@ -framework Foundation -framework CoreGraphics -framework ImageIO

aperture-chart: $(APERTURE_CHART)

synthetic-optical-chart: $(SYNTHETIC_OPTICAL_CHART)

$(APERTURE_CHART): $(APERTURE_CHART_BIN)
	mkdir -p outputs
	$(APERTURE_CHART_BIN) $(APERTURE_CHART)

$(SYNTHETIC_OPTICAL_CHART): $(SYNTHETIC_OPTICAL_CHART_BIN)
	$(SYNTHETIC_OPTICAL_CHART_BIN) $(SYNTHETIC_OPTICAL_CHART)

test: all
	$(TEST_BIN) $(METAL_LIB)

visual-test: all aperture-chart presets
	@printf '\n=== $(VISUAL_PASS_LABEL) ===\n'
	@for reference in "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" "$(ARRI_REVEAL_LUT)" '$(HAWK_REFERENCE)' '$(COOKE_SPECIAL_REFERENCE)'; do test -f "$$reference" || { echo "ERROR: Required validation reference is missing: $$reference" >&2; exit 1; }; done
	@set -e; staging="$(VALIDATION_ROOT)/.pass-$(VISUAL_PASS_ID).staging"; \
		test ! -e "$(VALIDATION_OUTPUT)" || { echo "ERROR: Archived visual pass already exists: $(VALIDATION_OUTPUT)" >&2; exit 1; }; \
		rm -rf "$$staging"; mkdir -p "$$staging" "$(VALIDATION_ROOT)/passes"; \
		trap 'rm -rf "$$staging"' EXIT; \
		$(VISUAL_BIN) $(METAL_LIB) "$$staging" "$(APERTURE_CHART)" "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" "$(VISUAL_PASS_ID)" "$(VISUAL_PASS_LABEL)" '$(HAWK_REFERENCE)' '$(COOKE_SPECIAL_REFERENCE)'; \
		test -f "$$staging/VISUAL-PASS-$(VISUAL_PASS_ID).txt" || { echo "ERROR: Visual Pass $(VISUAL_PASS_ID) produced no pass manifest." >&2; exit 1; }; \
		review_count="$$(awk '/^Primary review files:/{found=1;next} found && /^  [^ ]/{count++} END{print count+0}' "$$staging/VISUAL-PASS-$(VISUAL_PASS_ID).txt")"; \
		test "$$review_count" -gt 0 || { echo "ERROR: Visual Pass $(VISUAL_PASS_ID) declared no primary review files." >&2; exit 1; }; \
		awk '/^Primary review files:/{found=1;next} found && /^  [^ ]/{sub(/^  /, ""); print}' "$$staging/VISUAL-PASS-$(VISUAL_PASS_ID).txt" | while IFS= read -r review; do test -f "$$staging/$$review" || { echo "ERROR: Declared primary review file is missing: $$review" >&2; exit 1; }; done; \
		mv "$$staging" "$(VALIDATION_OUTPUT)"; \
		rm -f "$(VALIDATION_ROOT)/latest"; ln -s "passes/pass-$(VISUAL_PASS_ID)" "$(VALIDATION_ROOT)/latest"; \
		./scripts/prune-visual-passes.sh "$(VALIDATION_ROOT)/passes" 3; \
		trap - EXIT
	@printf '=== Completed: $(VISUAL_PASS_LABEL) ===\nOutput: $(VALIDATION_OUTPUT)\n\n'

# Deployment consumes an already-reviewed immutable visual pass. Rendering is
# deliberately explicit through `make visual-test`; validation must never try
# to overwrite or silently replace that archive.
visual-check:
	@test -d "$(VALIDATION_OUTPUT)" || { echo "ERROR: Reviewed visual pass is missing: $(VALIDATION_OUTPUT)" >&2; echo "Run: make visual-test" >&2; exit 1; }
	@test -f "$(VALIDATION_OUTPUT)/VISUAL-PASS-$(VISUAL_PASS_ID).txt" || { echo "ERROR: Visual pass marker is missing for Pass $(VISUAL_PASS_ID)." >&2; exit 1; }
	@test "$$(head -n 1 "$(VALIDATION_OUTPUT)/VISUAL-PASS-$(VISUAL_PASS_ID).txt")" = "$(VISUAL_PASS_LABEL)" || { echo "ERROR: Visual pass marker does not match the current pass label." >&2; exit 1; }
	@test "$$(find "$(VALIDATION_OUTPUT)" -maxdepth 1 -name '*.tiff' -type f | wc -l | tr -d ' ')" -gt 0 || { echo "ERROR: Reviewed visual pass contains no TIFF outputs." >&2; exit 1; }
	@printf 'PASS: reviewed immutable visual archive $(VALIDATION_OUTPUT)\n'

# Rebuild a curated current-architecture visual catalogue. Retired front-dirt,
# superseded flare experiments, duplicates and intermediate tuning renders are
# intentionally excluded. This is a new baseline, not a claim that historical
# binaries can be reconstructed.
# It is deliberately write-once so a later run cannot silently erase review
# material. Set REBUILD_ID to create another independently archived baseline.
REBUILD_ID ?= abi-v14-current
REBUILD_OUTPUT := $(VALIDATION_ROOT)/baselines/$(REBUILD_ID)
visual-rebuild: all aperture-chart presets
	@printf '\n=== Curated Visual Baseline Rebuild: $(REBUILD_ID) ===\n'
	@for reference in "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" "$(ARRI_REVEAL_LUT)" '$(HAWK_REFERENCE)' '$(COOKE_SPECIAL_REFERENCE)'; do test -f "$$reference" || { echo "ERROR: Required validation reference is missing: $$reference" >&2; exit 1; }; done
	@set -e; staging="$(VALIDATION_ROOT)/.baseline-$(REBUILD_ID).staging"; \
		test ! -e "$(REBUILD_OUTPUT)" || { echo "ERROR: Archived baseline already exists: $(REBUILD_OUTPUT)" >&2; exit 1; }; \
		rm -rf "$$staging"; mkdir -p "$$staging" "$(VALIDATION_ROOT)/baselines"; \
		trap 'rm -rf "$$staging"' EXIT; \
		$(VISUAL_BIN) $(METAL_LIB) "$$staging" "$(APERTURE_CHART)" "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" -1 "Curated Visual Baseline Rebuild $(REBUILD_ID)" '$(HAWK_REFERENCE)' '$(COOKE_SPECIAL_REFERENCE)'; \
		mv "$$staging" "$(REBUILD_OUTPUT)"; \
		trap - EXIT
	@printf '=== Completed Curated Visual Baseline ===\nOutput: $(REBUILD_OUTPUT)\n\n'

benchmark: all
	$(BENCHMARK_BIN) $(METAL_LIB)

clean:
	rm -rf $(BUILD)
