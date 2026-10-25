#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/Reader.app>
# It carries the privacy manifest and the export-compliance answer, asks for no permission, runs
# nothing in the background, and has none of the Debug-only code (`DemoMode` and its ready
# marker): those are compiled out by `#if DEBUG`.
set -euo pipefail
APP="$1"
PLIST="$APP/Info.plist"
BINARY="$APP/$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$PLIST")"
failed=0
fail() { echo "FAIL: $*"; failed=1; }

[[ -f "$APP/PrivacyInfo.xcprivacy" ]] || fail "PrivacyInfo.xcprivacy is not in the app bundle"
plutil -lint "$APP/PrivacyInfo.xcprivacy" || fail "PrivacyInfo.xcprivacy is not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$PLIST")" == "false" ]] \
  || fail "ITSAppUsesNonExemptEncryption is not false"
if /usr/libexec/PlistBuddy -c "Print UIBackgroundModes" "$PLIST" > /dev/null 2>&1; then
  fail "the app declares background modes; it needs none"
fi
# A usage description is a permission the app can ask for; adding one is a privacy change
# (CLAUDE.md › Privacy), made here, in PRIVACY.md and in ShipHygieneTests together.
usages="$(plutil -convert xml1 -o - "$PLIST" | grep -oE '<key>NS[A-Za-z]+UsageDescription</key>' || true)"
[[ -z "$usages" ]] || fail "the app asks for a permission: $(echo "$usages" | tr '\n' ' ')"
# Books come only from the server the reader names, over HTTPS: no exception to App Transport Security.
if /usr/libexec/PlistBuddy -c "Print NSAppTransportSecurity" "$PLIST" > /dev/null 2>&1; then
  fail "the app relaxes App Transport Security"
fi

# Type names survive in the binary as mangled metadata, the marker as a plain string. Stripping
# first drops the debug map, which names every object file whether or not it compiled to anything.
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"
for symbol in DemoMode demo-ready; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest, no permissions, no background modes, App Transport Security intact, no Debug-only code"
exit $failed
