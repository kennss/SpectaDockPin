#!/usr/bin/env bash
#
# @file        release.sh
# @description Builds the installable SpectaDockPin: archive (Release) -> export with the Developer ID identity
#              -> verify -> notarize + staple the app -> DMG -> sign, notarize + staple the DMG -> Sparkle
#              appcast. No Xcode UI. Run from anywhere; it cd's to the repo root. Same pipeline as SpectArk
#              (Docs/DESIGN.md §9).
#
#              Usage:
#                  ./scripts/release.sh                 # full pipeline (build + sign + notarize + dmg)
#                  SKIP_NOTARIZE=1 ./scripts/release.sh # build + sign + dmg only (no notarization)
#                  NOTARY_PROFILE=name ./scripts/release.sh   # override the keychain profile name
#
#              Notarization uses the existing notarytool keychain profile "WhisPlayInfo-notary" (same Developer
#              ID account, 8677QL77VJ, shared with SiliconScope and SpectArk). If it is missing, create it once:
#                  xcrun notarytool store-credentials WhisPlayInfo-notary \
#                      --apple-id <apple-id> --team-id 8677QL77VJ --password <app-specific-password>
#
#              Sparkle: the appcast is signed with the Calida Lab EdDSA key in the login keychain (shared with
#              SpectArk and SiliconScope; its public half is SUPublicEDKey in Info.plist). Upload BOTH the DMG
#              and appcast.xml to the v<version> GitHub release; SUFeedURL points at releases/latest. Raise
#              CURRENT_PROJECT_VERSION in project.yml for every release: Sparkle compares CFBundleVersion.
#              Release notes: Docs/release-notes/<version>.html, picked up automatically when present.
#
#              The Developer ID build is a different signature from the Apple Development builds Xcode makes,
#              so the Accessibility grant has to be given again once after installing it. Quit the app before
#              changing that permission (DESIGN §12).
#
# @author      Kennt Kim
# @company     Calida Lab
# @created     2026-10-18
# @lastUpdated 2026-10-19
#
set -euo pipefail

cd "$(dirname "$0")/.."                       # repo root

APP_NAME="SpectaDockPin"
PROJECT="SpectaDockPin.xcodeproj"
SCHEME="SpectaDockPin"
TEAM_ID="8677QL77VJ"
SIGN_ID="Developer ID Application: YONG SOO KIM (${TEAM_ID})"
NOTARY_PROFILE="${NOTARY_PROFILE:-WhisPlayInfo-notary}"

BUILD_DIR="build/release"
ARCHIVE="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
STAGING="${BUILD_DIR}/dmg-staging"

NOTARIZE=1; [ "${SKIP_NOTARIZE:-0}" = "1" ] && NOTARIZE=0

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate >/dev/null

echo "==> Archiving (Release)"
xcodebuild archive \
  -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release \
  -archivePath "${ARCHIVE}" -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates >/dev/null

echo "==> Exporting Developer ID app"
cat > "${BUILD_DIR}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
  -allowProvisioningUpdates >/dev/null

APP="${EXPORT_DIR}/${APP_NAME}.app"
[ -d "${APP}" ] || { echo "ERROR: ${APP} not found after export"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
DMG="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
echo "==> Built ${APP_NAME} ${VERSION}"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "${APP}"
codesign -dvv "${APP}" 2>&1 | grep -E 'Authority=|Runtime|TeamIdentifier' || true

if [ "${NOTARIZE}" = "1" ]; then
  echo "==> Notarizing app (may take a few minutes)"
  ZIP="${BUILD_DIR}/${APP_NAME}-notarize.zip"
  ditto -c -k --keepParent "${APP}" "${ZIP}"
  xcrun notarytool submit "${ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${APP}"
  rm -f "${ZIP}"
fi

echo "==> Building DMG"
rm -rf "${STAGING}"; mkdir -p "${STAGING}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}" >/dev/null
codesign --force --sign "${SIGN_ID}" --timestamp "${DMG}"

if [ "${NOTARIZE}" = "1" ]; then
  echo "==> Notarizing DMG (may take a few minutes)"
  xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}"
  echo "==> Gatekeeper check"
  spctl -a -t open --context context:primary-signature -vv "${DMG}" 2>&1 || true

  # Sparkle appcast: sign the FINAL (notarized + stapled) DMG with the EdDSA key in the login keychain.
  echo "==> Generating Sparkle appcast"
  APPCAST_TOOL="$(find "${HOME}/Library/Developer/Xcode/DerivedData/${PROJECT%.xcodeproj}-"*/SourcePackages/artifacts \
                       build/dd/SourcePackages/artifacts -name generate_appcast -type f 2>/dev/null | head -1)"
  if [ -n "${APPCAST_TOOL}" ]; then
    APPCAST_DIR="${BUILD_DIR}/appcast"
    rm -rf "${APPCAST_DIR}"; mkdir -p "${APPCAST_DIR}"
    cp "${DMG}" "${APPCAST_DIR}/"
    NOTES_SRC="Docs/release-notes/${VERSION}.html"
    if [ -f "${NOTES_SRC}" ]; then
      cp "${NOTES_SRC}" "${APPCAST_DIR}/${APP_NAME}-${VERSION}.html"
      echo "==> Bundled release notes from ${NOTES_SRC}"
    else
      echo "WARN: no ${NOTES_SRC} — the update window will show no release notes"
    fi
    "${APPCAST_TOOL}" --download-url-prefix "https://github.com/kennss/${APP_NAME}/releases/download/v${VERSION}/" "${APPCAST_DIR}"
    cp "${APPCAST_DIR}/appcast.xml" "${BUILD_DIR}/appcast.xml"
    echo "==> appcast: ${BUILD_DIR}/appcast.xml"
  else
    echo "ERROR: generate_appcast not found — build once so SwiftPM fetches Sparkle, then re-run."
    exit 1
  fi
else
  echo "==> SKIP_NOTARIZE set — signed but NOT notarized (no appcast)"
fi

echo "==> Done: ${DMG}"
ls -lh "${DMG}"
if [ "${NOTARIZE}" = "1" ]; then
  echo ""
  echo "Publish (uploads BOTH the DMG and the appcast so auto-update sees it):"
  echo "  gh release create v${VERSION} \"${DMG}\" \"${BUILD_DIR}/appcast.xml\" --repo kennss/${APP_NAME} --title \"${APP_NAME} ${VERSION}\" --notes \"...\""
fi
