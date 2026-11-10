#!/bin/zsh
# Собирает Overtext.app (arm64 + Intel).
#   ./build.sh            — собрать build/Overtext.app
#   ./build.sh --install  — собрать и положить в /Applications (запускать — самому)
#   ./build.sh --release  — собрать архив build/Overtext-<версия>.zip для GitHub
set -e
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1 && [[ -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

APP=build/Overtext.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/*.swift -o build/obj/Overtext-$arch
done
lipo -create build/obj/Overtext-arm64 build/obj/Overtext-x86_64 -output "$APP/Contents/MacOS/Overtext"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f Assets/AppIcon.icns ]] && cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Постоянный сертификат «markdev» (Связка ключей → Ассистент сертификатов → Создать сертификат,
# тип «Подпись кода») — тогда «Универсальный доступ» не слетает после каждой пересборки.
if security find-identity -p codesigning 2>/dev/null | grep -q '"markdev"'; then
  codesign --force --sign "markdev" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Собрано: $APP ($(lipo -archs "$APP/Contents/MacOS/Overtext"))"

if [[ "$1" == "--install" ]]; then
  rm -rf /Applications/Overtext.app
  cp -R "$APP" /Applications/Overtext.app
  echo "Установлено в /Applications/Overtext.app"
fi

if [[ "$1" == "--release" ]]; then
  VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
  ZIP=build/Overtext-$VER.zip
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Архив: $ZIP"
  shasum -a 256 "$ZIP"
fi
