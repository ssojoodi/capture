PROJECT := Capture.xcodeproj
SCHEME := Capture
APP_NAME := Capture
RELEASE_ENV ?= release.env

-include $(RELEASE_ENV)

CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS
DERIVED_DATA ?= .build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
INSTALL_APP := /Applications/$(APP_NAME).app
RELEASE_SOURCE_APP := .build/release/DerivedData/Build/Products/Release/$(APP_NAME).app

BRAND_DIR := Brand
BRAND_BUILD_DIR := .build/BrandAssets
SWIFT_MODULE_CACHE := .build/ModuleCache
SWIFT := swift -module-cache-path $(SWIFT_MODULE_CACHE)
XCODEBUILD := xcrun xcodebuild

SVG_RENDERER := scripts/render_svg.swift
DMG_BACKGROUND_RENDERER := scripts/render_dmg_background.swift
DMG_SCRIPT := scripts/create_dmg.sh
LOGO_SVG := $(BRAND_DIR)/logo.svg
APP_ICON_SVG := $(BRAND_DIR)/app-icon.svg
LOGO_PNG := $(BRAND_BUILD_DIR)/logo.png
APP_ICON_PNG := $(BRAND_BUILD_DIR)/app-icon.png
DMG_BACKGROUND_PNG := $(BRAND_BUILD_DIR)/dmg-background.png
ASSETCATALOG_DIR := Sources/CaptureApp/Assets.xcassets
APPICONSET_DIR := $(ASSETCATALOG_DIR)/AppIcon.appiconset
APP_ICON_FILES := $(APPICONSET_DIR)/icon_*.png
APP_ICON_SPECS := \
	icon_16x16.png:16 \
	icon_16x16@2x.png:32 \
	icon_32x32.png:32 \
	icon_32x32@2x.png:64 \
	icon_128x128.png:128 \
	icon_128x128@2x.png:256 \
	icon_256x256.png:256 \
	icon_256x256@2x.png:512 \
	icon_512x512.png:512 \
	icon_512x512@2x.png:1024

.DEFAULT_GOAL := build

.PHONY: assets build buildlocal clean help paths release check-release run test uninstall

assets: $(LOGO_PNG) $(APP_ICON_PNG) $(DMG_BACKGROUND_PNG)
	mkdir -p "$(APPICONSET_DIR)"
	for spec in $(APP_ICON_SPECS); do \
		name=$${spec%:*}; \
		size=$${spec#*:}; \
		sips -z $$size $$size "$(APP_ICON_PNG)" --out "$(APPICONSET_DIR)/$$name" >/dev/null; \
	done

$(LOGO_PNG): $(LOGO_SVG) $(SVG_RENDERER)
	mkdir -p "$(BRAND_BUILD_DIR)" "$(SWIFT_MODULE_CACHE)"
	$(SWIFT) "$(SVG_RENDERER)" "$(LOGO_SVG)" "$(LOGO_PNG)" 1200 320

$(APP_ICON_PNG): $(APP_ICON_SVG) $(SVG_RENDERER)
	mkdir -p "$(BRAND_BUILD_DIR)" "$(SWIFT_MODULE_CACHE)"
	$(SWIFT) "$(SVG_RENDERER)" "$(APP_ICON_SVG)" "$(APP_ICON_PNG)" 1024 1024

$(DMG_BACKGROUND_PNG): $(DMG_BACKGROUND_RENDERER)
	mkdir -p "$(BRAND_BUILD_DIR)" "$(SWIFT_MODULE_CACHE)"
	$(SWIFT) "$(DMG_BACKGROUND_RENDERER)" "$(DMG_BACKGROUND_PNG)"

build: assets
	$(XCODEBUILD) build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)"

buildlocal: assets
	$(XCODEBUILD) build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO

clean:
	$(XCODEBUILD) clean \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)"
	rm -rf "$(BRAND_BUILD_DIR)"
	rm -rf "$(DERIVED_DATA)"
	rm -rf ".build/release"
	rm -rf "$(SWIFT_MODULE_CACHE)"
	rm -f $(APP_ICON_FILES)

test: assets
	$(XCODEBUILD) test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)"

run: build
	open "$(APP)"

uninstall:
	rm -rf "$(INSTALL_APP)"

release:
	python3 scripts/release.py --identity "$(SIGN_IDENTITY)" --profile "$(NOTARY_PROFILE)"

check-release:
	python3 scripts/check_release_workflow.py
	python3 scripts/check_release_publication.py


paths:
	@printf "Built app: %s\n" "$(APP)"
	@printf "Release app: %s\n" "$(RELEASE_SOURCE_APP)"
	@printf "DMG: web-page/%s.dmg\n" "$(APP_NAME)"
	@printf "Logo PNG: %s\n" "$(LOGO_PNG)"
	@printf "App icon PNG: %s\n" "$(APP_ICON_PNG)"
	@printf "DMG background PNG: %s\n" "$(DMG_BACKGROUND_PNG)"

help:
	@printf "Targets:\n"
	@printf "  make             Build Capture\n"
	@printf "  make assets      Regenerate app icon PNGs and DMG background\n"
	@printf "  make buildlocal  Build with Xcode signing disabled\n"
	@printf "  make clean       Clean build products, generated assets, and release output\n"
	@printf "  make test        Run unit tests\n"
	@printf "  make run         Build and open the app\n"
	@printf "  make uninstall   Remove /Applications/Capture.app\n"
	@printf "  make release     Build, validate, and move the DMG to web-page\n"
	@printf "  make check-release  Test release workflow without credentials\n"
	@printf "  make paths       Print important generated paths\n"
	@printf "\nVariables:\n"
	@printf "  CONFIGURATION=Debug|Release  Default: Debug\n"
	@printf "  DERIVED_DATA=.build/DerivedData\n"
	@printf "  Version/build: edit Config/Version.xcconfig\n"
	@printf "  RELEASE_ENV=release.env     Local ignored release config\n"
