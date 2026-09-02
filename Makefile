SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
MOBILE_METAL_BIN := $(dir $(firstword $(wildcard /private/var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-*/Metal.xctoolchain/usr/bin/metal)))
METAL := $(if $(MOBILE_METAL_BIN),$(MOBILE_METAL_BIN)metal,$(shell xcrun --find metal))
METALLIB := $(if $(MOBILE_METAL_BIN),$(MOBILE_METAL_BIN)metallib,$(shell xcrun --find metallib))
CXX := xcrun clang++
BUILD := build
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/$(BUILD)/module-cache
METAL_AIR := $(BUILD)/LDBOptics.air
METAL_LIB := $(BUILD)/LDBOptics.metallib
TEST_BIN := $(BUILD)/ldb-optics-tests
VISUAL_BIN := $(BUILD)/ldb-optics-visual-validation
BENCHMARK_BIN := $(BUILD)/ldb-optics-benchmark
APERTURE_CHART_BIN := $(BUILD)/ldb-aperture-chart
APERTURE_CHART := outputs/aperture-pupil-test-acescg-linear.tiff
RESOLVE_OFX := /Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/OpenFX
OFX_INCLUDE := $(RESOLVE_OFX)/OpenFX-1.4/include
OFX_SUPPORT_INCLUDE := $(RESOLVE_OFX)/Support/include
OFX_SUPPORT_LIBRARY := $(RESOLVE_OFX)/Support/Library
OFX_BUILD := $(BUILD)/ofx
OFX_BUNDLE := $(BUILD)/LensDebaser.ofx.bundle
OFX_BINARY := $(OFX_BUNDLE)/Contents/MacOS/LensDebaser.ofx
OFX_SUPPORT_SOURCES := ofxsCore ofxsImageEffect ofxsInteract ofxsLog ofxsMultiThread ofxsParams ofxsProperty ofxsPropertyValidation
OFX_SUPPORT_OBJECTS := $(addprefix $(OFX_BUILD)/,$(addsuffix .o,$(OFX_SUPPORT_SOURCES)))
ISO_CHART ?= /Users/blacktar/Desktop/ISO_12233-reschart.tif
REAL_FOOTAGE ?= /Users/blacktar/Desktop/iphone_milano_dwg_1.tif
ARRI_FOOTAGE ?= /Users/blacktar/Desktop/arri_log00086400.tif
ARRI_REVEAL_LUT ?= /Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT/Arri/ARRI_LogC4_v1_LUT_Package/LUTs/ARRI_LogC4-to-Gamma24_Rec709-D65_v1-65.cube
VALIDATION_OUTPUT := outputs/engine-validation

.PHONY: all ofx validate deploy aperture-chart install install-user test clean

all: $(METAL_LIB) $(TEST_BIN) $(VISUAL_BIN) $(BENCHMARK_BIN)

ofx: $(OFX_BINARY)

install: install-user

validate: test benchmark visual-test

# One command for a Resolve test build: validate the engine and visual outputs,
# then install only if every preceding step succeeds.
deploy:
	@if pgrep -x "Resolve" >/dev/null; then echo "ERROR: Fully quit DaVinci Resolve before deployment." >&2; exit 1; fi
	@test -d "$(OFX_INCLUDE)" || { echo "ERROR: Resolve OpenFX SDK is unavailable at $(OFX_INCLUDE)." >&2; exit 1; }
	@test -x "$(METAL)" && test -x "$(METALLIB)" || { echo "ERROR: Apple Metal compiler tools are unavailable." >&2; exit 1; }
	@for reference in "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" "$(ARRI_REVEAL_LUT)"; do test -f "$$reference" || { echo "ERROR: Required validation reference is missing: $$reference" >&2; exit 1; }; done
	$(MAKE) validate
	@printf '\nInspect $(VALIDATION_OUTPUT), especially newly changed optical renders.\nInstall this build into Resolve? [y/N] '; \
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

visual-test: all aperture-chart
	@for reference in "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)" "$(ARRI_REVEAL_LUT)"; do test -f "$$reference" || { echo "ERROR: Required validation reference is missing: $$reference" >&2; exit 1; }; done
	@set -e; staging="$(VALIDATION_OUTPUT).staging"; previous="$(VALIDATION_OUTPUT).previous"; \
		rm -rf "$$staging"; mkdir -p "$$staging"; \
		trap 'rm -rf "$$staging"' EXIT; \
		$(VISUAL_BIN) $(METAL_LIB) "$$staging" "$(APERTURE_CHART)" "$(ISO_CHART)" "$(REAL_FOOTAGE)" "$(ARRI_FOOTAGE)"; \
		rm -rf "$$previous"; \
		if test -d "$(VALIDATION_OUTPUT)"; then mv "$(VALIDATION_OUTPUT)" "$$previous"; fi; \
		if mv "$$staging" "$(VALIDATION_OUTPUT)"; then rm -rf "$$previous"; else if test -d "$$previous"; then mv "$$previous" "$(VALIDATION_OUTPUT)"; fi; exit 1; fi; \
		trap - EXIT

benchmark: all
	$(BENCHMARK_BIN) $(METAL_LIB)

clean:
	rm -rf $(BUILD)
