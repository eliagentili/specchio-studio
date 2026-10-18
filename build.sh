#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="Specchio Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/cache
python3 Native/build_native.py
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path .build/cache -import-objc-header Native/WirelessBridge.h Sources/*.swift -o "$APP/Contents/MacOS/SpecchioStudio" -framework SwiftUI -framework AppKit -framework AVFoundation -framework CoreMediaIO -framework CoreImage -framework ScreenCaptureKit -framework Vision -framework VideoToolbox -framework AudioToolbox -framework Security .build/native/libSpecchioAirPlay.a ThirdParty/OpenSSL/lib/libcrypto.a -lz
cp Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
for language in en it; do
    rm -rf "$APP/Contents/Resources/$language.lproj"
    cp -R "Resources/$language.lproj" "$APP/Contents/Resources/"
done
python3 scripts/bundle_licenses.py "$APP/Contents/Resources/Licenses"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
print "App ready: ${PWD}/$APP"
