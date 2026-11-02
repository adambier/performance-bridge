#!/bin/bash
# Build Performance Bridge and wrap it in a .app bundle. Modeled on pgdata Packer's make-app.sh
# (adambier/3rd-wave-tools).
#
#   ./make-app.sh              release build for this Mac
#   ./make-app.sh debug        debug build
#   ./make-app.sh --universal  release build for Apple Silicon and Intel (one binary; for a release)
#   ./make-app.sh --zip        also write Performance-Bridge-<version>.zip, for a GitHub release
#   ./make-app.sh --sign "Developer ID Application: Name (TEAMID)"
#                              sign with that identity (hardened runtime, timestamp) instead of
#                              the ad-hoc signature; `security find-identity -v -p codesigning`
#                              lists the identities in your keychain
#   ./make-app.sh --notarize   after signing, submit the app to Apple's notary service, wait for
#                              the result, and staple the ticket; needs --sign and a notarytool
#                              keychain profile named "performance-bridge", made once with
#                              xcrun notarytool store-credentials "performance-bridge" --apple-id … --team-id …
#   ./make-app.sh --appcast    with --zip and --universal, add the zip to ./appcast.xml with Sparkle's
#                              generate_appcast (signs it with the EdDSA key in your keychain, account
#                              org.biers.performancebridge; the download URL is the GitHub release for
#                              tag v<version>); commit appcast.xml to main once the release is published
#   ./make-app.sh --feed-url=URL
#                              use this update feed instead of the public one (to test updates
#                              against a local appcast; not allowed with --notarize or --appcast)
#
# A release build for distribution: ./make-app.sh --universal --sign "…" --notarize --zip --appcast
#
# In-app updates use Sparkle 2. The first build downloads the pinned Sparkle release into build/
# (checked against its SHA-256), so it needs a network connection; later builds reuse it. The app
# links against it and embeds Sparkle.framework.
#
# The result is "./Performance Bridge.app": double-clickable, no Xcode needed; the Command Line
# Tools are enough (xcode-select --install). SwiftPM is not used: every library folder and the app
# are compiled straight into one module with swiftc, so the app's cross-library imports are wrapped
# in `#if canImport(...)` and compile out, and no two top-level declarations may share a name
# (CI type-checks this build). `swift run PerformanceBridge` remains the quick way to try the app.

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
MAKE_ZIP=0
UNIVERSAL=0
SIGN_IDENTITY=""
NOTARIZE=0
NOTARY_PROFILE="performance-bridge"   # xcrun notarytool store-credentials "performance-bridge" …
MAKE_APPCAST=0
SPARKLE_KEY_ACCOUNT="org.biers.performancebridge"   # the keychain account of the EdDSA private key
# Sparkle reads the update feed from here. Permanent once a release with it has shipped.
FEED_URL="https://raw.githubusercontent.com/adambier/performance-bridge/main/appcast.xml"
FEED_OVERRIDDEN=0
EXPECT_IDENTITY=0
for arg in "$@"; do
    if [ "$EXPECT_IDENTITY" -eq 1 ]; then
        case "$arg" in --*) echo "--sign needs an identity, not \"$arg\"." >&2; exit 2 ;; esac
        SIGN_IDENTITY="$arg"; EXPECT_IDENTITY=0; continue
    fi
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --zip) MAKE_ZIP=1 ;;
        --universal) UNIVERSAL=1 ;;
        --sign) EXPECT_IDENTITY=1 ;;
        --sign=*) SIGN_IDENTITY="${arg#--sign=}" ;;
        --notarize) NOTARIZE=1 ;;
        --appcast) MAKE_APPCAST=1 ;;
        --feed-url=*) FEED_URL="${arg#--feed-url=}"; FEED_OVERRIDDEN=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done
if [ "$EXPECT_IDENTITY" -eq 1 ] || { [ "$NOTARIZE" -eq 1 ] && [ -z "$SIGN_IDENTITY" ]; }; then
    echo "--sign needs an identity, and --notarize needs --sign." >&2
    exit 2
fi
if [ "$MAKE_APPCAST" -eq 1 ] && { [ "$MAKE_ZIP" -eq 0 ] || [ "$UNIVERSAL" -eq 0 ]; }; then
    # generate_appcast reads the architectures from the app: a one-architecture build would hide
    # the update from the other kind of Mac.
    echo "--appcast needs --zip and --universal." >&2
    exit 2
fi
if [ "$FEED_OVERRIDDEN" -eq 1 ] && { [ "$NOTARIZE" -eq 1 ] || [ "$MAKE_APPCAST" -eq 1 ]; }; then
    # A released app with a test feed would never see another update.
    echo "--feed-url is for test builds; it cannot be combined with --notarize or --appcast." >&2
    exit 2
fi

APP="Performance Bridge.app"
EXECUTABLE="PerformanceBridge"
BUNDLE_ID="org.biers.performancebridge"
ARCH="$(uname -m)"
VERSION="0.1.0"
# The build number must rise with every release (an updater compares it): the number of commits.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DEPLOYMENT_TARGET="13.0"
# The copyright line the Finder's Get Info shows (NSHumanReadableCopyright): the year of first
# publication through the year of this build, kept current by the build itself.
FIRST_YEAR="2026"
THIS_YEAR="$(date +%Y)"
COPYRIGHT_YEARS="$FIRST_YEAR"
if [ "$THIS_YEAR" -gt "$FIRST_YEAR" ]; then COPYRIGHT_YEARS="${FIRST_YEAR}–${THIS_YEAR}"; fi
COPYRIGHT="Copyright © $COPYRIGHT_YEARS Adam Arthur Bier. MIT License."

# A second item for the same version would carry a new build number and signature but point at the
# same download, which then fails to verify if the uploaded zip is not this run's. Checked before
# the build so that a long notarization is not wasted.
if [ "$MAKE_APPCAST" -eq 1 ] && [ -f appcast.xml ] \
    && grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml; then
    echo "appcast.xml already has an item for $VERSION. Remove that item first if it should be replaced." >&2
    exit 2
fi

# Sparkle 2, for in-app updates. The public half of the app's own EdDSA key (the private half is in
# the release signer's keychain, account org.biers.performancebridge). The SHA-256 is of the
# release archive as downloaded from GitHub on 2026-10-31.
SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE_PUBLIC_ED_KEY="KTt3BYFC8qH22G0zlWbtdfe7E9OGSw14LgkrZQCmfC4="
SPARKLE_DIR="build/Sparkle-$SPARKLE_VERSION"   # the distribution archive, extracted

mkdir -p build

if [ ! -d "$SPARKLE_DIR/Sparkle.framework" ]; then
    SPARKLE_ARCHIVE="build/Sparkle-$SPARKLE_VERSION.tar.xz"
    echo "Downloading Sparkle ${SPARKLE_VERSION}…"
    curl -fsSL -o "$SPARKLE_ARCHIVE" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    if [ "$(shasum -a 256 "$SPARKLE_ARCHIVE" | cut -d ' ' -f 1)" != "$SPARKLE_SHA256" ]; then
        echo "The Sparkle download does not match its expected SHA-256; not using it." >&2
        rm -f "$SPARKLE_ARCHIVE"
        exit 1
    fi
    rm -rf "$SPARKLE_DIR.partial"
    mkdir -p "$SPARKLE_DIR.partial"
    tar -xf "$SPARKLE_ARCHIVE" -C "$SPARKLE_DIR.partial"
    rm -rf "$SPARKLE_DIR"
    mv "$SPARKLE_DIR.partial" "$SPARKLE_DIR"
    rm -f "$SPARKLE_ARCHIVE"
fi

SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
    echo "Could not locate the macOS SDK. Run: xcode-select --install" >&2
    exit 1
fi
BIN="build/$EXECUTABLE"

if [ "$CONFIG" = "release" ]; then
    OPTFLAGS=(-O -whole-module-optimization)
else
    OPTFLAGS=(-Onone -g)
fi
ARCHS=("$ARCH")
if [ "$UNIVERSAL" -eq 1 ]; then ARCHS=(arm64 x86_64); fi   # one binary for Apple Silicon and Intel

# Every library the app uses, and the app. Not sbdev (the developer tool).
SOURCES=(
    Sources/OSCCodec/*.swift
    Sources/TotalMixOSC/*.swift
    Sources/RotoControl/*.swift
    Sources/MIDITransport/*.swift
    Sources/UDPTransport/*.swift
    Sources/SurfaceCore/*.swift
    Sources/RotoDriver/*.swift
    Sources/LaunchControl/*.swift
    Sources/LaunchControlDriver/*.swift
    Sources/BridgeEngine/*.swift
    App/PerformanceBridge/*.swift
)

echo "Building with swiftc ($CONFIG, ${ARCHS[*]})…"
echo "  SDK: $SDK"

SLICES=()
for A in "${ARCHS[@]}"; do
    SLICE="build/$EXECUTABLE-$A"
    swiftc \
        "${OPTFLAGS[@]}" \
        -parse-as-library \
        -sdk "$SDK" \
        -target "${A}-apple-macos${DEPLOYMENT_TARGET}" \
        -module-name "$EXECUTABLE" \
        -framework AppKit \
        -framework SwiftUI \
        -framework CoreMIDI \
        -F "$SPARKLE_DIR" \
        -framework Sparkle \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -o "$SLICE" \
        "${SOURCES[@]}"
    SLICES+=("$SLICE")
done
if [ "${#SLICES[@]}" -gt 1 ]; then
    lipo -create "${SLICES[@]}" -output "$BIN"
else
    cp "${SLICES[0]}" "$BIN"
fi

if [ ! -x "$BIN" ]; then
    echo "Build produced no binary at $BIN" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
# The Finder's icon, from the icon set in Design/AppIcon; the About window's icon and the menu-bar
# glyph are the app's own resources (Brand in PerformanceBridgeApp.swift reads them from the bundle).
iconutil -c icns Design/AppIcon/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp App/PerformanceBridge/Resources/*.png "$APP/Contents/Resources/"

# Sparkle.framework, copied with ditto to keep its symlinks and executable bits. The app is not
# sandboxed, so Sparkle's XPC services are not used; Sparkle's docs allow removing them.
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$SPARKLE_FW"
rm -rf "$SPARKLE_FW/XPCServices" "$SPARKLE_FW/Versions/B/XPCServices"
# Sparkle's MIT license asks for its notice to go with every copy.
cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"

# LSUIElement: a menu-bar app, with no Dock icon and no menu bar of its own. The app also sets this
# at launch (setActivationPolicy(.accessory)) for `swift run`, where there is no Info.plist.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>       <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>             <string>Performance Bridge</string>
    <key>CFBundleDisplayName</key>      <string>Performance Bridge</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>          <string>$BUILD_NUMBER</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>   <string>$DEPLOYMENT_TARGET</string>
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
    <key>NSHumanReadableCopyright</key> <string>$COPYRIGHT</string>
    <key>NSPrincipalClass</key>         <string>NSApplication</string>
    <key>SUFeedURL</key>                <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>            <string>$SPARKLE_PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

# Signed inside-out, never with --deep: Sparkle's helper tool and app, then the framework (removing
# the XPC services invalidated its signature), then the app.
SIGN_ORDER=("$SPARKLE_FW/Versions/B/Autoupdate" "$SPARKLE_FW/Versions/B/Updater.app" "$SPARKLE_FW" "$APP")
if [ -n "$SIGN_IDENTITY" ]; then
    # Developer ID signature with the hardened runtime and a secure timestamp, as notarization
    # requires. The app has no entitlements: nothing it does needs an exception from the runtime
    # (UDP on the local network and CoreMIDI need none outside the sandbox).
    echo "Signing with \"$SIGN_IDENTITY\"…"
    for ITEM in "${SIGN_ORDER[@]}"; do
        codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$ITEM"
    done
    codesign --verify --deep --strict --verbose=2 "$APP"
else
    # An unsigned arm64 app is killed at launch, so the ad-hoc signature is required for any
    # build that includes an Apple Silicon slice. An ad-hoc signed app opens on the Mac that built
    # it; elsewhere macOS warns.
    for ITEM in "${SIGN_ORDER[@]}"; do
        if ! codesign --force --sign - "$ITEM"; then
            echo "codesign failed on $ITEM: the app will not launch on Apple Silicon without an ad-hoc signature." >&2
            exit 1
        fi
    done
fi

if [ "$NOTARIZE" -eq 1 ]; then
    # Submit a zip of the app (ditto keeps the bundle's metadata and signature, which zip does
    # not), wait for Apple's verdict, then staple the ticket to the app so Gatekeeper can check
    # it offline. The zip for distribution is made afterward, from the stapled app.
    NOTARIZE_ZIP="build/notarize.zip"
    rm -f "$NOTARIZE_ZIP"
    ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
    echo "Submitting to Apple's notary service (profile \"$NOTARY_PROFILE\")…"
    if ! xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
        echo "Notarization failed. For the reasons:  xcrun notarytool log <submission id> --keychain-profile \"$NOTARY_PROFILE\"" >&2
        exit 1
    fi
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

# A copy already running would only be brought forward by `open`, so quit it: then `open` starts
# the build just made (Adam, 2026-10-31).
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
    pkill -x "$EXECUTABLE" || true
    echo "Quit the running copy of Performance Bridge."
fi

echo
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null || echo "$ARCH"), version $VERSION, build $BUILD_NUMBER)"
echo "Run it with:  open \"$APP\""

ZIP="Performance-Bridge-$VERSION.zip"
if [ "$MAKE_ZIP" -eq 1 ]; then
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Wrote $ZIP"
fi

if [ "$MAKE_APPCAST" -eq 1 ]; then
    # generate_appcast works on a folder of archives and updates the appcast.xml in it: a fresh
    # folder holding the current appcast.xml (if any) and only this release's zip, so the download
    # URL prefix applies to this release alone and the earlier items keep their URLs. The release
    # notes, hw-tests/release-notes-<version>.md if present, go next to the zip under its base name
    # and are embedded in the item for Sparkle's update window. Their "## Download" section, which
    # is about the zip on the GitHub release page, is left out of the update window.
    APPCAST_DIR="build/appcast"
    rm -rf "$APPCAST_DIR"
    mkdir -p "$APPCAST_DIR"
    if [ -f appcast.xml ]; then cp appcast.xml "$APPCAST_DIR/appcast.xml"; fi
    cp "$ZIP" "$APPCAST_DIR/"
    NOTES="hw-tests/release-notes-$VERSION.md"
    if [ -f "$NOTES" ]; then
        # Drop from a "## Download" heading to the next "## " heading (or the end).
        awk '/^## /{ skip = ($0 ~ /^## Download[[:space:]]*$/) } !skip' "$NOTES" \
            > "$APPCAST_DIR/Performance-Bridge-$VERSION.md"
    else
        echo "No $NOTES: the update will have no release notes." >&2
    fi
    "$SPARKLE_DIR/bin/generate_appcast" \
        --account "$SPARKLE_KEY_ACCOUNT" \
        --download-url-prefix "https://github.com/adambier/performance-bridge/releases/download/v$VERSION/" \
        --embed-release-notes \
        --maximum-versions 0 \
        --maximum-deltas 0 \
        "$APPCAST_DIR"
    cp "$APPCAST_DIR/appcast.xml" appcast.xml
    echo "Updated appcast.xml; commit it to main once the v$VERSION release with $ZIP is published."
fi
