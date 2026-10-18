#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache .build/test-results
python3 Native/build_native.py
# Instrument the pairing implementation itself, not only its test caller.
clang -target arm64-apple-macos14.0 -O1 -g -fsanitize=address -fno-omit-frame-pointer -DOPENSSL_API_COMPAT=0x10101000L -DPLIST_210 -DPLIST_230 -IThirdParty/UxPlay/lib -IThirdParty/libplist/include -IThirdParty/OpenSSL/include Tests/PairingTests.c ThirdParty/UxPlay/lib/pairing.c ThirdParty/UxPlay/lib/srp.c ThirdParty/UxPlay/lib/crypto.c ThirdParty/UxPlay/lib/utils.c .build/native/libSpecchioAirPlay.a ThirdParty/OpenSSL/lib/libcrypto.a -lz -o .build/PairingTests
clang -target arm64-apple-macos14.0 -fobjc-arc -fmodules -fmodules-cache-path=.build/native/modules Tests/WirelessNativeTests.m .build/native/libSpecchioAirPlay.a ThirdParty/OpenSSL/lib/libcrypto.a -framework Foundation -framework VideoToolbox -framework AudioToolbox -framework CoreMedia -framework CoreVideo -framework Security -lz -o .build/WirelessNativeTests
swiftc -D STUDIO_TEST -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 -module-cache-path .build/cache -import-objc-header Native/WirelessBridge.h Sources/*.swift Tests/*.swift -o .build/StudioTests -framework SwiftUI -framework AppKit -framework AVFoundation -framework CoreMediaIO -framework CoreImage -framework ScreenCaptureKit -framework Vision -framework VideoToolbox -framework AudioToolbox -framework Security .build/native/libSpecchioAirPlay.a ThirdParty/OpenSSL/lib/libcrypto.a -lz
if [[ "${1:-}" != "--build-only" ]]; then
  ASAN_OPTIONS=halt_on_error=1 .build/PairingTests
  .build/WirelessNativeTests Tests/Fixtures/wireless.h264 Tests/Fixtures/wireless.hevc
  .build/StudioTests "${PWD}/.build/test-results" "${PWD}/Tests/Fixtures/synthetic-audio.mov"
fi
