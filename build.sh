#!/bin/sh
# Builds pzx on Linux (GTK2) or macOS (Cocoa).
#
#   ./build.sh                 uses lazbuild from an installed Lazarus
#   LAZARUS_DIR=/path ./build.sh   compiles with fpc against that Lazarus
#                              source tree (no Lazarus install needed)
#
# Output goes to build/<os>/: the pzx executable plus the roms folder
# (on macOS, a pzx.app bundle). Sound needs SDL2 at run time
# (Linux: libsdl2-2.0-0, macOS: brew install sdl2); without it pzx runs silent.
set -e
cd "$(dirname "$0")"

case "$(uname -s)" in
  Darwin) OS=macos; WS=cocoa ;;
  *)      OS=linux; WS=gtk2 ;;
esac
OUT="build/$OS"
UNITS="$OUT/units"
mkdir -p "$UNITS"

if [ -n "$LAZARUS_DIR" ]; then
  L="$LAZARUS_DIR"
  fpc -O2 -MObjFPC -Scghi -dLCL -dLCL$WS \
    -Fu"$L/components/lazutils" -Fi"$L/components/lazutils" \
    -Fu"$L/components/freetype" -Fu"$L/lcl" -Fu"$L/lcl/widgetset" -Fu"$L/lcl/forms" \
    -Fu"$L/lcl/nonwin32" -Fu"$L/lcl/interfaces/$WS" \
    -Fi"$L/lcl/include" -Fi"$L/lcl/interfaces/$WS" \
    -Fusrc -FU"$UNITS" -FE"$OUT" -o"$OUT/pzx" src/pzx.lpr
else
  command -v lazbuild >/dev/null || {
    echo "lazbuild not found: install Lazarus or set LAZARUS_DIR to a Lazarus source tree" >&2
    exit 1
  }
  lazbuild --ws="$WS" src/pzx.lpi
  mv -f src/pzx "$OUT/pzx"
fi

if [ "$OS" = macos ]; then
  APP="$OUT/pzx.app/Contents"
  mkdir -p "$APP/MacOS" "$APP/Resources"
  mv -f "$OUT/pzx" "$APP/MacOS/pzx"
  rm -rf "$APP/MacOS/roms"
  cp -R roms "$APP/MacOS/roms"
  cp README.md LICENSE "$APP/MacOS/"
  rm -rf "$APP/MacOS/esxdos"
  cp -R esxdos "$APP/MacOS/esxdos"
  rm -rf "$APP/MacOS/zxuno"
  cp -R zxuno "$APP/MacOS/zxuno"
  # Empty: the ZX Spectrum Next distribution is the user's to add
  mkdir -p "$APP/MacOS/specnext"
  cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>pzx</string>
  <key>CFBundleIdentifier</key><string>org.pzx.emulator</string>
  <key>CFBundleName</key><string>pzx</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
  echo "Built $OUT/pzx.app"
else
  rm -rf "$OUT/roms"
  cp -R roms "$OUT/roms"
  cp README.md LICENSE "$OUT/"
  rm -rf "$OUT/esxdos"
  cp -R esxdos "$OUT/esxdos"
  rm -rf "$OUT/zxuno"
  cp -R zxuno "$OUT/zxuno"
  mkdir -p "$OUT/specnext"
  echo "Built $OUT/pzx"
fi
