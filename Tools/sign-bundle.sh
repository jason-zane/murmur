#!/bin/sh
set -eu
bundle=$1
identity=$2
entitlements=$3
timestamp=--timestamp=none
options=runtime
case "$identity" in 'Developer ID Application'*) timestamp=--timestamp ;; esac
# CI's ad-hoc candidates have no Team ID, so hardened library validation cannot
# load Sparkle. Local re-signing restores hardened runtime with the stable identity.
case "$identity" in -) options=0 ;; esac

# Sign nested code inside out. Sparkle's vendor signature cannot be used with the
# app's hardened runtime/library validation, so every helper uses our stable identity.
framework="$bundle/Contents/Frameworks/Sparkle.framework"
if [ -d "$framework" ]; then
    for helper in "$framework/Versions/B/XPCServices/Downloader.xpc" \
                  "$framework/Versions/B/XPCServices/Installer.xpc" \
                  "$framework/Versions/B/Updater.app" \
                  "$framework/Versions/B/Autoupdate"; do
        codesign --force --sign "$identity" --options "$options" "$timestamp" "$helper"
    done
    codesign --force --sign "$identity" --options "$options" "$timestamp" "$framework"
fi
codesign --force --sign "$identity" --options "$options" "$timestamp" "$bundle/Contents/MacOS/murmur-mcp"
codesign --force --sign "$identity" --options "$options" "$timestamp" --entitlements "$entitlements" "$bundle"
codesign --verify --deep --strict "$bundle"
