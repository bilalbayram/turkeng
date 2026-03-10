#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>  (e.g. 1.1.0)}"
TAG="v${VERSION}"
DMG="turkeng-${VERSION}.dmg"

echo "==> Building turkeng ${TAG}"
tuist install && tuist generate

xcodebuild -workspace turkeng.xcworkspace -scheme turkeng \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="3N28465E96" \
  CODE_SIGN_STYLE="Manual" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  MARKETING_VERSION="${VERSION}" \
  clean build

echo "==> Notarizing app"
ditto -c -k --keepParent build/Build/Products/Release/turkeng.app /tmp/turkeng-notarize.zip
xcrun notarytool submit /tmp/turkeng-notarize.zip --keychain-profile "notary" --wait
xcrun stapler staple build/Build/Products/Release/turkeng.app

echo "==> Creating DMG"
rm -rf /tmp/turkeng-dmg
mkdir /tmp/turkeng-dmg
cp -R build/Build/Products/Release/turkeng.app /tmp/turkeng-dmg/
ln -s /Applications /tmp/turkeng-dmg/Applications
hdiutil create -volname turkeng -srcfolder /tmp/turkeng-dmg -ov -format UDZO "${DMG}"

echo "==> Notarizing DMG"
xcrun notarytool submit "${DMG}" --keychain-profile "notary" --wait
xcrun stapler staple "${DMG}"

echo "==> Publishing GitHub release ${TAG}"
gh release create "${TAG}" "${DMG}" \
  --title "turkeng ${TAG}" \
  --generate-notes

echo "==> Cleaning up"
rm -rf build /tmp/turkeng-dmg /tmp/turkeng-notarize.zip "${DMG}"

echo "==> Done! https://github.com/bilalbayram/turkeng/releases/tag/${TAG}"
