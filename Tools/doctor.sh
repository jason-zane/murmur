#!/bin/sh
# Toolchain and signing check for building Voice Notes. Prints one line per item and the
# fix when something is missing. Exits non-zero if the build cannot succeed.
status=0
ok()   { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; }
bad()  { printf '  ✗ %s\n' "$1"; status=1; }

echo "Xcode"
if dev=$(xcode-select -p 2>/dev/null); then
  ok "$dev"
else
  bad "no developer directory — install Xcode 26 from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
fi

echo "Swift"
if ver=$(swift --version 2>/dev/null | head -1 | sed -E 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/'); then
  major=${ver%%.*}; minor=${ver#*.}
  if [ "$major" -gt 6 ] 2>/dev/null || { [ "$major" -eq 6 ] && [ "$minor" -ge 2 ]; }; then
    ok "Swift $ver"
  else
    bad "Swift $ver — Package.swift needs 6.2 (Xcode 26). Select a newer Xcode: sudo xcode-select -s /Applications/Xcode.app"
  fi
else
  bad "swift not found"
fi

echo "macOS SDK"
if sdk=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null); then
  case "$sdk" in
    26.*|2[7-9].*) ok "macOS $sdk SDK" ;;
    *) bad "macOS $sdk SDK — the app targets macOS 26; install Xcode 26" ;;
  esac
else
  bad "no macOS SDK — install Xcode and its Command Line Tools"
fi

echo "Code signing"
case "$SIGN_ID" in
  "-"|"") warn "ad-hoc — builds work, but every rebuild resets the Accessibility grant. An Apple Development certificate (free with an Apple ID in Xcode ▸ Settings ▸ Accounts) fixes that." ;;
  *"Developer ID"*) ok "$SIGN_ID" ;;
  *) ok "$SIGN_ID"; warn "not a Developer ID certificate — fine for personal use and for friends who Open Anyway; not for notarised distribution" ;;
esac

echo "Tools"
command -v python3 >/dev/null 2>&1 && ok "python3 $(python3 --version 2>&1 | cut -d' ' -f2) (smoke tests, preview fixtures)" || warn "python3 missing — Tools/smoke-mcp.py and preview fixtures need it"
if command -v node >/dev/null 2>&1; then
  nodev=$(node --version | sed 's/^v//'); nodemajor=${nodev%%.*}
  if [ "$nodemajor" -ge 24 ] 2>/dev/null; then ok "node $nodev (web/)"; else warn "node $nodev — web/ wants 24 or newer (only needed for the hosted backend)"; fi
else
  warn "node missing — only needed to work on web/"
fi

echo "Installed app"
if [ -d /Applications/Murmur.app ]; then
  if pgrep -x Murmur >/dev/null 2>&1; then
    running=$(ps -o comm= -p "$(pgrep -x Murmur | head -1)")
    case "$running" in
      /Applications/Murmur.app/*) ok "/Applications/Murmur.app is the running copy" ;;
      *) warn "Voice Notes is running from $running, not /Applications — login item and Claude Desktop point at the Applications copy" ;;
    esac
  else
    ok "/Applications/Murmur.app installed (not running)"
  fi
else
  warn "not installed — make install"
fi

exit $status
