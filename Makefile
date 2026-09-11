EXEC     := Murmur
MCP      := murmur-mcp
MODELS   := murmur-models
CONFIG   ?= debug
LAUNCH   ?= 1
TEST_ARGS ?=

## What the app reports about itself. Tagged commits give "0.5.0"; anything else gives
## the short hash, which the update check treats as "not a release" and leaves alone.
VERSION      ?= $(shell git describe --tags --match 'v*' --always --dirty 2>/dev/null | sed -E 's/^v//')
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
## The hosted backend the app signs in to. Self-hosters point this at their own deployment.
SITE_URL     ?= https://murmur-rho-pied.vercel.app

## Build products live OUTSIDE this directory. Checkouts under a file-provider-synced
## folder (Desktop, Documents, iCloud Drive) get their files mutated and xattr-stamped
## while the compiler and codesign are using them; ~/Library/Caches is never synced.
SCRATCH  := $(HOME)/Library/Caches/MurmurBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)
MCPBUILD := $(SCRATCH)/$(CONFIG)/$(MCP)
STAGE    := $(HOME)/Library/Caches/MurmurBuild
APPNAME  := Murmur.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents
DIST     := dist

## TCC keys the Accessibility grant to the code *signature*, not the path. An ad-hoc
## signature is regenerated on every build, so the rebuilt binary no longer satisfies the
## stored requirement — and the symptom lies: the Accessibility toggle still shows as ON
## while the app is reported untrusted, and toggling it changes nothing.
##
## So we sign with a real, stable identity. Preference order:
##   1. "Developer ID Application" — the distributable identity, if one exists.
##   2. "Apple Development"        — a personal cert. Not distributable, but stable across
##                                   rebuilds, which is the property TCC actually cares
##                                   about. This is the identity used on this machine.
##   3. Ad-hoc ("-")               — last resort; expect to re-grant after every build.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/')
endif
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: all build test app run install clean icon release dist package doctor

all: app

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

test:
	@cmp shared/dictionary-test-vectors.json Tests/MurmurDictionaryTests/dictionary-test-vectors.json
	swift test --scratch-path "$(SCRATCH)" $(TEST_ARGS)

## Regenerates AppIcon.icns from Tools/makeicon.swift. Not a dependency of `app` — the
## icon rarely changes and rendering 10 PNGs on every build is wasted time.
icon:
	@swift Tools/makeicon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

## Assemble a real .app bundle. TCC (microphone + Accessibility) keys on bundle identity
## and code signature, so the raw SwiftPM binary can't be used directly.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp $(BUILD) "$(CONTENTS)/MacOS/$(EXEC)"
	@# The MCP server ships inside the bundle so Claude Desktop has one stable path to
	@# spawn: /Applications/Murmur.app/Contents/MacOS/murmur-mcp. It is signed on its own
	@# first — codesign does not descend into MacOS/ for helper executables.
	@cp $(MCPBUILD) "$(CONTENTS)/MacOS/$(MCP)"
	@codesign --force --sign "$(SIGN_ID)" --options runtime --timestamp=none "$(CONTENTS)/MacOS/$(MCP)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(CONTENTS)/Info.plist"
	@plutil -replace VoiceNotesSiteURL -string "$(SITE_URL)" "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Belt and braces: the staging dir isn't synced, but the copied binary can still carry
	@# xattrs inherited from the synced .build directory.
	@xattr -cr "$(BUNDLE)"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "built $(BUNDLE) $(VERSION) ($(BUILD_NUMBER))  [signed: $(SIGN_ID)]"

## Only ever targets the Murmur executable — never the separate `murmur` app.
run: install

## Ad-hoc signatures change on every rebuild, which resets the Accessibility grant.
## Installing to /Applications keeps the path stable and makes re-granting a one-click fix.
install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@# $(BUNDLE) is an absolute staging path — the destination must use $(APPNAME) alone.
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@if [ "$(LAUNCH)" = "1" ]; then open "/Applications/$(APPNAME)"; fi
	@echo "installed to /Applications/$(APPNAME)"

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)" "$(DIST)"

## An optimised build of the bundle. Same staging path; `install` and `dist` take it from there.
release:
	@$(MAKE) --no-print-directory app CONFIG=release

## A disk image with an Applications shortcut, so dragging lands the app where the login
## item and the Claude Desktop connection expect it. `ZIP=1` produces a zip instead.
## Not notarised: first launch needs Privacy & Security ▸ Open Anyway (see docs/INSTALL.md).
dist:
	@$(MAKE) --no-print-directory app CONFIG=release
	@$(MAKE) --no-print-directory package CONFIG=release

package:
	@codesign --verify --deep --strict "$(BUNDLE)"
	@if [ "$(SIGN_ID)" = "-" ]; then \
		echo "warning: ad-hoc signature — every update will reset the Accessibility grant on the user's Mac"; fi
	@mkdir -p "$(DIST)"
	@rm -rf "$(STAGE)/dist-staging" && mkdir -p "$(STAGE)/dist-staging"
	@if [ "$(ZIP)" = "1" ]; then \
		ditto -c -k --keepParent "$(BUNDLE)" "$(DIST)/VoiceNotes-$(VERSION).zip"; \
		echo "wrote $(DIST)/VoiceNotes-$(VERSION).zip"; \
	else \
		cp -R "$(BUNDLE)" "$(STAGE)/dist-staging/"; \
		ln -s /Applications "$(STAGE)/dist-staging/Applications"; \
		hdiutil create -volname "Voice Notes" -srcfolder "$(STAGE)/dist-staging" -format UDZO -ov \
			"$(DIST)/VoiceNotes-$(VERSION).dmg" >/dev/null; \
		echo "wrote $(DIST)/VoiceNotes-$(VERSION).dmg"; \
	fi
	@rm -rf "$(STAGE)/dist-staging"

## Checks the toolchain and signing identity, and says what to fix.
doctor:
	@SIGN_ID="$(SIGN_ID)" sh Tools/doctor.sh

## Pre-seed the optional on-device models from a terminal (the app can do the same from
## Settings). `make models` fetches everything; `make models WHICH=speakers` one of them.
WHICH ?= all
.PHONY: models
models:
	swift build --scratch-path $(SCRATCH) --product $(MODELS)
	$(SCRATCH)/$(CONFIG)/$(MODELS) download $(WHICH)
