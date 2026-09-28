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
GUIDE_EXAMPLES_BIN := $(BUILD)/ldb-guide-examples
GUIDE_EXAMPLES_DIR := docs/user-guide/images/examples
APERTURE_CHART := outputs/aperture-pupil-test-acescg-linear.tiff
RESOLVE_OFX := /Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/OpenFX
OFX_INCLUDE := $(RESOLVE_OFX)/OpenFX-1.4/include
OFX_SUPPORT_INCLUDE := $(RESOLVE_OFX)/Support/include
OFX_SUPPORT_LIBRARY := $(RESOLVE_OFX)/Support/Library
OFX_BUILD := $(BUILD)/ofx
OFX_BUNDLE := $(BUILD)/LensDebaser.ofx.bundle
OFX_BINARY := $(OFX_BUNDLE)/Contents/MacOS/LensDebaser.ofx
PRODUCT_LABEL := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleName' resources/Info.plist 2>/dev/null)
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
VISUAL_PASS_ID := 85
VISUAL_PASS_LABEL := Visual Pass $(VISUAL_PASS_ID) - Inward-Sampled Prism Refraction
VALIDATION_OUTPUT := $(VALIDATION_ROOT)/passes/pass-$(VISUAL_PASS_ID)

.PHONY: all ofx validate performance-test deploy release aperture-chart guide-examples user-guide presets preset-test install install-user test visual-test visual-check visual-rebuild clean

all: $(METAL_LIB) $(TEST_BIN) $(VISUAL_BIN) $(BENCHMARK_BIN)

ofx: $(OFX_BINARY)

install: install-user

release: validate ofx
	./scripts/package-release.sh

# Deployment validation is a correctness and visual-output gate. Keep the
# sustained benchmark explicit: it is sensitive to machine load and thermal
# state, and is required when processing changes rather than for every install.
validate: preset-test test visual-check

performance-test: benchmark

presets:
	./scripts/generate-presets.py

preset-test: presets
	@test "$$(find presets/demonstrations presets/cinematic-lenses -name '*.ldbpreset' -type f | wc -l | tr -d ' ')" = 101 || { echo "ERROR: Expected 101 generated factory presets." >&2; exit 1; }
	@! grep -REn '^(inputWorkingSpace|diagnosticView|depthSource)=' presets/demonstrations presets/cinematic-lenses || { echo "ERROR: A processing-only or removed control was serialized in a factory preset." >&2; exit 1; }

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

$(TEST_BIN): tests/MetalEngineTests.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h include/LDBColorReference.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/MetalEngineTests.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal

$(VISUAL_BIN): tests/VisualValidation.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h include/LDBColorReference.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/VisualValidation.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal -framework CoreGraphics -framework ImageIO

$(GUIDE_EXAMPLES_BIN): tests/GuideExamples.mm tests/VisualValidation.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h include/LDBColorReference.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude -Itests tests/GuideExamples.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal -framework CoreGraphics -framework ImageIO

guide-examples: $(METAL_LIB) $(GUIDE_EXAMPLES_BIN) presets
	@for reference in inputs/redistributable/ISO_12233-reschart.tif inputs/redistributable/OGC-TERA-CHART-1.png inputs/redistributable/iphone_milano_dwg_1.tif inputs/redistributable/iphone_milano2___dwg.tif inputs/redistributable/iphone_milano3_dwg.tif inputs/redistributable/Resolve-DWG-Intermediate-to-Rec709-Gamma24-Guide.cube; do test -f "$$reference" || { echo "ERROR: Required guide source is missing: $$reference" >&2; exit 1; }; done
	rm -rf "$(GUIDE_EXAMPLES_DIR)"
	mkdir -p "$(GUIDE_EXAMPLES_DIR)"
	$(GUIDE_EXAMPLES_BIN) $(METAL_LIB) "$(CURDIR)" "$(GUIDE_EXAMPLES_DIR)"
	./scripts/build-user-guide.py

user-guide:
	./scripts/build-user-guide.py

$(BENCHMARK_BIN): tests/MetalBenchmark.mm src/engine/LDBOpticsEngine.mm include/LDBOpticsEngine.h include/LDBOpticsParameters.h | $(BUILD)
	$(CXX) -std=c++20 -fobjc-arc -arch arm64 -Iinclude tests/MetalBenchmark.mm src/engine/LDBOpticsEngine.mm -o $@ -framework Foundation -framework Metal

$(APERTURE_CHART_BIN): tests/ApertureChartGenerator.cpp | $(BUILD)
	$(CXX) -std=c++20 -arch arm64 $< -o $@

aperture-chart: $(APERTURE_CHART)

$(APERTURE_CHART): $(APERTURE_CHART_BIN)
	mkdir -p outputs
	$(APERTURE_CHART_BIN) $(APERTURE_CHART)

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
