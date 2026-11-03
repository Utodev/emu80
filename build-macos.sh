#!/bin/sh
# Builds ochenta for macOS (Cocoa) as a complete ochenta.app, run on a Mac.
#
#   ./build-macos.sh [options]
#
#   --lazbuild PATH   the lazbuild to use (default: $LAZBUILD, then lazbuild on the PATH, then
#                     /Applications/Lazarus/lazbuild and ~/lazarus/lazbuild)
#   --cpu CPU         aarch64 (Apple Silicon), x86_64 (Intel) or universal (both, joined with lipo);
#                     default: this Mac's
#   --sdl PATH|none   the SDL2 library put inside the app for the sound (default: Homebrew's,
#                     /opt/homebrew or /usr/local; none = the app uses the one installed, if any)
#   --sign IDENTITY   code signing identity (default: - , an ad hoc signature, enough to run it
#                     on this Mac; a "Developer ID Application: ..." one for others)
#   --dmg             also makes build/macos/ochenta-VERSION-macos.dmg
#   --out DIR         where ochenta.app goes (default: build/macos)
#   -h, --help        this text
#
# The app has ochenta in Contents/MacOS and everything that comes with it in Contents/Resources:
# roms (without the original MSX and Commodore 64 ROMs, which are never distributed), esxdos, zxuno,
# README.md, LICENSE and the icon; SDL2 in Contents/Frameworks. ochenta keeps its settings, the ZX
# Spectrum Next distribution (specnext) and the user's own ROMs (roms/c64, roms/msx) in
# ~/Library/Application Support/ochenta (or uses an ochenta.ini next to ochenta.app if there is one).
set -e
cd "$(dirname "$0")"
ROOT=$(pwd)

usage() { sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

LAZ="${LAZBUILD:-}"
CPU=""
SDL=""
SIGN="-"
DMG=0
OUT="build/macos"
while [ $# -gt 0 ]; do
  case "$1" in
    --lazbuild) LAZ="$2"; shift 2 ;;
    --lazbuild=*) LAZ="${1#*=}"; shift ;;
    --cpu) CPU="$2"; shift 2 ;;
    --cpu=*) CPU="${1#*=}"; shift ;;
    --sdl) SDL="$2"; shift 2 ;;
    --sdl=*) SDL="${1#*=}"; shift ;;
    --sign) SIGN="$2"; shift 2 ;;
    --sign=*) SIGN="${1#*=}"; shift ;;
    --dmg) DMG=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --out=*) OUT="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || { echo "build-macos.sh runs on macOS" >&2; exit 1; }

# lazbuild: as given, or the usual places
if [ -z "$LAZ" ]; then
  for L in "$(command -v lazbuild 2>/dev/null)" /Applications/Lazarus/lazbuild "$HOME/lazarus/lazbuild" \
           /Applications/lazarus/lazbuild /usr/local/bin/lazbuild /opt/homebrew/bin/lazbuild; do
    if [ -n "$L" ] && [ -x "$L" ]; then LAZ="$L"; break; fi
  done
fi
[ -n "$LAZ" ] || { echo "lazbuild not found: give it with --lazbuild /path/to/lazbuild" >&2; exit 1; }
[ -x "$LAZ" ] || { echo "$LAZ is not an executable lazbuild" >&2; exit 1; }
echo "Using $LAZ"

if [ -z "$CPU" ]; then
  case "$(uname -m)" in arm64) CPU=aarch64 ;; *) CPU=x86_64 ;; esac
fi
case "$CPU" in
  aarch64|arm64) CPUS=aarch64 ;;
  x86_64|intel) CPUS=x86_64 ;;
  universal) CPUS="aarch64 x86_64" ;;
  *) echo "--cpu must be aarch64, x86_64 or universal" >&2; exit 1 ;;
esac

# The release number: the build's date and time (see CLAUDE.md)
printf "{ Release number: the build date and time (YYYYMMDDHHMM), written before every build (see CLAUDE.md) }\nconst\n  OCHENTA_RELEASE = '%s';\n" "$(date +%Y%m%d%H%M)" > src/Release.inc
VERSION=$(sed -n "s/.*OCHENTA_RELEASE = '\([0-9]*\)'.*/\1/p" src/Release.inc)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The executable, for each CPU
BINS=""
for C in $CPUS; do
  echo "Building for $C..."
  rm -f src/ochenta
  if ! "$LAZ" --ws=cocoa --os=darwin --cpu="$C" src/ochenta.lpi > "$WORK/lazbuild-$C.log" 2>&1; then
    tail -30 "$WORK/lazbuild-$C.log" >&2
    echo "lazbuild failed for $C" >&2
    exit 1
  fi
  mv -f src/ochenta "$WORK/ochenta-$C"
  BINS="$BINS $WORK/ochenta-$C"
done

# The bundle
APPDIR="$OUT/ochenta.app"
APP="$APPDIR/Contents"
rm -rf "$APPDIR"
mkdir -p "$APP/MacOS" "$APP/Resources" "$APP/Frameworks"
if [ "$CPU" = universal ]; then
  lipo -create $BINS -output "$APP/MacOS/ochenta"
else
  cp $BINS "$APP/MacOS/ochenta"
fi
chmod 755 "$APP/MacOS/ochenta"

# What comes with ochenta, in Resources (where it looks for it)
cp -R roms esxdos zxuno "$APP/Resources/"
cp README.md LICENSE "$APP/Resources/"
# The ROMs that are never distributed: the user's (in ~/Library/Application Support/ochenta/roms)
for F in msx/MSX2.rom msx/MSX2EXT.rom msx/PHILIPSDISK.rom c64/Kernal.rom c64/Basic.rom c64/Char.rom c64/VC1541.rom; do
  rm -f "$APP/Resources/roms/$F"
done
find "$APP/Resources" -name '.DS_Store' -delete
for F in QUANTIKA.ROM QUANTIKA_SUB.ROM QUANTIKA_DISK.ROM; do
  [ -f "$APP/Resources/roms/msx/$F" ] || echo "Warning: roms/msx/$F is missing: the MSX2 won't start" >&2
done

# The icon: the biggest picture of src/ochenta.ico, in every size macOS wants
ICONSET="$WORK/ochenta.iconset"
mkdir -p "$ICONSET"
if command -v python3 >/dev/null; then
  python3 - src/ochenta.ico "$WORK/icon.png" <<'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read()
count = struct.unpack_from('<H', data, 4)[0]
best = None
for i in range(count):
    w, h, _, _, _, _, size, offset = struct.unpack_from('<BBBBHHII', data, 6 + i * 16)
    w = w or 256
    if best is None or w > best[0]:
        best = (w, size, offset)
open(sys.argv[2], 'wb').write(data[best[2]:best[2] + best[1]])
EOF
fi
# (an entry that is a bitmap, not a PNG, or no python3: sips converts the .ico)
if ! [ -s "$WORK/icon.png" ] || ! sips -g pixelWidth "$WORK/icon.png" >/dev/null 2>&1; then
  sips -s format png src/ochenta.ico --out "$WORK/icon.png" >/dev/null
fi
for S in 16 32 128 256 512; do
  sips -z $S $S "$WORK/icon.png" --out "$ICONSET/icon_${S}x${S}.png" >/dev/null
  D=$((S * 2))
  sips -z $D $D "$WORK/icon.png" --out "$ICONSET/icon_${S}x${S}@2x.png" >/dev/null
done
ICON_KEY=""
if iconutil -c icns "$ICONSET" -o "$APP/Resources/ochenta.icns" 2>/dev/null; then
  ICON_KEY="<key>CFBundleIconFile</key><string>ochenta</string>"
else
  echo "Warning: the icon could not be made: the app has the default one" >&2
fi

# SDL2 for the sound, inside the app
if [ "$SDL" != none ]; then
  if [ -z "$SDL" ]; then
    for L in /opt/homebrew/lib/libSDL2-2.0.0.dylib /usr/local/lib/libSDL2-2.0.0.dylib; do
      if [ -f "$L" ]; then SDL="$L"; break; fi
    done
  fi
  if [ -n "$SDL" ] && [ -f "$SDL" ]; then
    cp -L "$SDL" "$APP/Frameworks/libSDL2-2.0.0.dylib"
    chmod 755 "$APP/Frameworks/libSDL2-2.0.0.dylib"
    install_name_tool -id @rpath/libSDL2-2.0.0.dylib "$APP/Frameworks/libSDL2-2.0.0.dylib" 2>/dev/null || true
    # It must need nothing but the system's own libraries
    if otool -L "$APP/Frameworks/libSDL2-2.0.0.dylib" | tail -n +2 | grep -v -e '/System/Library/' -e '/usr/lib/' \
         -e '@rpath/libSDL2' | grep -q .; then
      echo "Warning: $SDL needs other libraries that are not in the app:" >&2
      otool -L "$APP/Frameworks/libSDL2-2.0.0.dylib" | tail -n +2 >&2
    fi
    for C in $CPUS; do
      case "$C" in aarch64) A=arm64 ;; *) A=x86_64 ;; esac
      lipo -archs "$APP/Frameworks/libSDL2-2.0.0.dylib" | grep -qw "$A" ||
        echo "Warning: $SDL has no $A code: no sound on that kind of Mac" >&2
    done
  else
    echo "Warning: SDL2 not found (brew install sdl2, or --sdl PATH): the app uses the one installed, if any" >&2
  fi
fi
rmdir "$APP/Frameworks" 2>/dev/null || true

cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>ochenta</string>
  <key>CFBundleExecutable</key><string>ochenta</string>
  $ICON_KEY
  <key>CFBundleIdentifier</key><string>org.ochenta.emulator</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>ochenta</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key><string>10.13</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>See LICENSE</string>
</dict>
</plist>
EOF
printf 'APPL????' > "$APP/PkgInfo"

# Signed (ad hoc by default: Apple Silicon runs nothing unsigned)
xattr -cr "$APPDIR" 2>/dev/null || true
if [ -d "$APP/Frameworks" ]; then
  codesign --force --sign "$SIGN" "$APP/Frameworks/libSDL2-2.0.0.dylib"
fi
if [ "$SIGN" = "-" ]; then
  codesign --force --sign - "$APPDIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGN" "$APPDIR"
fi
codesign --verify --strict "$APPDIR" || { echo "The app's signature does not verify" >&2; exit 1; }
echo "Built $APPDIR ($CPU, release $VERSION)"

if [ "$DMG" = 1 ]; then
  DMGFILE="$OUT/ochenta-$VERSION-macos.dmg"
  STAGE="$WORK/dmg"
  mkdir -p "$STAGE"
  cp -R "$APPDIR" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMGFILE"
  hdiutil create -volname "ochenta" -srcfolder "$STAGE" -ov -format UDZO "$DMGFILE" >/dev/null
  [ "$SIGN" = "-" ] || codesign --force --sign "$SIGN" "$DMGFILE"
  echo "Built $DMGFILE"
fi
