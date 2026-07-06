PROJECT := Capture.xcodeproj
SCHEME := Capture
APP_NAME := Capture
RELEASE_ENV ?= release.env

-include $(RELEASE_ENV)

CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS
DERIVED_DATA ?= .build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
RELEASE_DIR ?= .build/release
RELEASE_STAGING := $(RELEASE_DIR)/staging
RELEASE_APP := $(RELEASE_STAGING)/$(APP_NAME).app
RELEASE_SOURCE_APP := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
VERSION ?= $(shell date +%Y.%m.%d.%H%M)
DMG := $(RELEASE_DIR)/$(APP_NAME)-$(VERSION).dmg
XCODEBUILD := xcrun xcodebuild

.DEFAULT_GOAL := build

.PHONY: build clean test run release help

build:
	$(XCODEBUILD) build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)"

clean:
	$(XCODEBUILD) clean \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)"
	rm -rf "$(DERIVED_DATA)"
	rm -rf "$(RELEASE_DIR)"

test:
	$(XCODEBUILD) test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)"

run: build
	open "$(APP)"

release:
	@if [ -z "$(strip $(SIGN_IDENTITY))" ]; then \
		printf "SIGN_IDENTITY is required.\n"; \
		printf "Example:\n"; \
		printf "  cp release.env.example release.env\n"; \
		printf "  security find-identity -v -p codesigning\n"; \
		exit 1; \
	fi
	@if [ -z "$(strip $(NOTARY_PROFILE))" ]; then \
		printf "NOTARY_PROFILE is required.\n"; \
		printf "Create one with:\n"; \
		printf "  xcrun notarytool store-credentials \"capture-notary\" --apple-id \"you@example.com\" --team-id \"TEAMID\" --password \"APP-SPECIFIC-PASSWORD\"\n"; \
		printf "Then set NOTARY_PROFILE = capture-notary in release.env.\n"; \
		exit 1; \
	fi
	$(MAKE) build CONFIGURATION=Release
	rm -rf "$(RELEASE_STAGING)" "$(DMG)"
	mkdir -p "$(RELEASE_STAGING)"
	ditto "$(RELEASE_SOURCE_APP)" "$(RELEASE_APP)"
	ln -s /Applications "$(RELEASE_STAGING)/Applications"
	codesign --force --deep --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$(RELEASE_APP)"
	codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP)"
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(RELEASE_STAGING)" \
		-ov \
		-format UDZO \
		"$(DMG)"
	codesign --force --timestamp --sign "$(SIGN_IDENTITY)" "$(DMG)"
	codesign --verify --verbose=2 "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	xcrun stapler validate "$(DMG)"
	spctl -a -t open --context context:primary-signature -v "$(DMG)"
	@printf "Created signed and notarized DMG: %s\n" "$(DMG)"

help:
	@printf "Targets:\n"
	@printf "  make        Build Capture\n"
	@printf "  make clean  Clean Xcode build products and derived data\n"
	@printf "  make test   Run unit tests\n"
	@printf "  make run    Build and open the app\n"
	@printf "  make release\n"
	@printf "              Build, sign, package, notarize, staple, and validate a DMG\n"
	@printf "\nVariables:\n"
	@printf "  CONFIGURATION=Debug|Release  Default: Debug\n"
	@printf "  DERIVED_DATA=.build/DerivedData\n"
	@printf "  VERSION=2026.06.30.2230     Default: current timestamp\n"
	@printf "  RELEASE_DIR=.build/release\n"
	@printf "  RELEASE_ENV=release.env     Local ignored release config\n"
