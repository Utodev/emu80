#!/bin/sh
# Makes .deb and .rpm packages of the Linux build (run build.sh first) and
# a .zip of the Windows one (ochenta.exe in this folder, built with lazbuild).
#
#   ./package.sh            the packages, into build/packages/
#
# The .zip has an ochenta-VERSION-windows folder with ochenta.exe, roms, esxdos,
# zxuno, README.md and LICENSE (ochenta.ini is made there when ochenta closes), and a
# lib folder with the native library for host applications (ochentalib.dll) and
# its documentation (LIBRARY.md), and a tests folder with the C# host demo
# (tests/csharp/OchentaHostDemo: its sources, build.bat and, in the .zip, the
# program built, which runs with --selftest). The library is built, if it
# isn't there, with src/lib/build-lib.sh.
# The MSX2's ROMs (roms/msx/QUANTIKA.ROM, QUANTIKA_SUB.ROM and QUANTIKA_DISK.ROM) are built first from their own project,
# ../quantika (its build.sh and install.sh); without it, the ones already in roms/msx go. The original MSX
# ROMs that may be in roms/msx (MSX2.rom, MSX2EXT.rom, PHILIPSDISK.rom) are never packaged, nor are the Commodore 64's (roms/c64:
# Kernal.rom, Basic.rom, Char.rom, VC1541.rom): the folder goes empty.
# The .AppImage needs appimagetool (see the end of this file).
# The .deb needs dpkg-deb (Debian, Ubuntu); the .rpm needs rpmbuild
# (Debian/Ubuntu: sudo apt install rpm; Fedora: sudo dnf install rpm-build).
# RPMBUILD=command uses another rpmbuild.
#
# Installed layout: the program, roms, esxdos, zxuno, README.md and LICENSE
# in /usr/lib/ochenta (ochenta finds them next to itself), and its lib folder with
# libochenta.so and LIBRARY.md, and its tests folder with the C# demo's sources, /usr/bin/ochenta to start it,
# a desktop entry and the icon. The settings go to ~/.config/ochenta/ochenta.ini,
# as /usr/lib/ochenta can't be written. The version is the release number
# (src/Release.inc). Sound needs SDL2, recommended by both packages.
set -e
cd "$(dirname "$0")"
ROOT=$(pwd)

VERSION=$(sed -n "s/.*OCHENTA_RELEASE = '\([0-9]*\)'.*/\1/p" src/Release.inc)
[ -n "$VERSION" ] || { echo "No release number in src/Release.inc" >&2; exit 1; }
MAINTAINER="Uto <csanchez@kioskoymas.com>"
SUMMARY="8 bit machines emulator (ZX Spectrum, ZX-Uno, ZX Spectrum Next, Amstrad CPC, SAM Coupe, MSX2)"
OUT="$ROOT/build/packages"
mkdir -p "$OUT"

# The MSX2's ROMs, from their project next to this one
QUANTIKA="$ROOT/../quantika"
if [ -x "$QUANTIKA/build.sh" ]; then
  "$QUANTIKA/build.sh" > "$OUT/quantika.log" 2>&1 || { cat "$OUT/quantika.log" >&2; echo "The QUANTIKA ROMs did not build" >&2; exit 1; }
  "$QUANTIKA/install.sh" "$ROOT/roms/msx"
else
  echo "../quantika not found: the QUANTIKA ROMs in roms/msx go as they are" >&2
fi
[ -f roms/msx/QUANTIKA.ROM ] && [ -f roms/msx/QUANTIKA_SUB.ROM ] && [ -f roms/msx/QUANTIKA_DISK.ROM ] || {
  echo "roms/msx/QUANTIKA.ROM, QUANTIKA_SUB.ROM or QUANTIKA_DISK.ROM is missing" >&2; exit 1; }
# Files of roms that are never distributed (the original MSX ROMs, supplied by the user)
NOT_PACKAGED="msx/MSX2.rom msx/MSX2EXT.rom msx/PHILIPSDISK.rom c64/Kernal.rom c64/Basic.rom c64/Char.rom c64/VC1541.rom"

# The native library, for the packages' lib folder (built here if needed)
if [ ! -f build/lib/ochentalib.dll ]; then
  src/lib/build-lib.sh >/dev/null 2>&1 || echo "Could not build ochentalib.dll: the .zip has no lib folder" >&2
fi
if [ ! -f build/lib/libochenta.so ]; then
  src/lib/build-lib.sh linux >/dev/null 2>&1 || echo "Could not build libochenta.so: no lib folder in the .deb and .rpm" >&2
fi

# The C# host demo, built (Windows only) for the .zip
DEMO=tests/csharp/OchentaHostDemo
if [ -f build/lib/ochentalib.dll ] && command -v cmd.exe >/dev/null; then
  (cd "$DEMO" && cmd.exe /c build.bat >/dev/null 2>&1) || echo "Could not build the C# demo: the .zip has its sources only" >&2
fi

# Windows: a .zip of ochenta.exe and its folders
if [ -f ochenta.exe ]; then
  ZIP="ochenta-$VERSION-windows"
  rm -f "$OUT/$ZIP.zip"
  NOT_PACKAGED="$NOT_PACKAGED" python3 - "$OUT/$ZIP.zip" "$ZIP" ochenta.exe roms esxdos zxuno README.md LICENSE <<'EOF'
import os, sys, zipfile
out, top, names = sys.argv[1], sys.argv[2], sys.argv[3:]
skip = {os.path.join('roms', f) for f in os.environ['NOT_PACKAGED'].split()}
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in names:
        if os.path.isdir(name):
            for folder, dirs, files in os.walk(name):
                dirs.sort()
                for f in sorted(files):
                    path = os.path.join(folder, f)
                    if os.path.normpath(path) in skip:
                        continue
                    z.write(path, os.path.join(top, path))
        else:
            z.write(name, os.path.join(top, name))
    # The native library and its documentation
    if os.path.exists('build/lib/ochentalib.dll'):
        z.write('build/lib/ochentalib.dll', top + '/lib/ochentalib.dll')
        z.write('LIBRARY.md', top + '/lib/LIBRARY.md')
    # The C# host demo: sources, build.bat, and the program built if it is
    for f in ('Ochenta.cs', 'Program.cs', 'build.bat'):
        z.write('tests/csharp/OchentaHostDemo/' + f, top + '/tests/OchentaHostDemo/' + f)
    if os.path.exists('build/csharp/OchentaHostDemo.exe') and os.path.exists('build/lib/ochentalib.dll'):
        z.write('build/csharp/OchentaHostDemo.exe', top + '/tests/OchentaHostDemo/OchentaHostDemo.exe')
        z.write('build/lib/ochentalib.dll', top + '/tests/OchentaHostDemo/ochentalib.dll')
    # The empty folder for the ZX Spectrum Next distribution (never its contents)
    z.writestr(top + '/specnext/', '')
    # ... and for the Commodore 64's ROMs, which are the user's
    z.writestr(top + '/roms/c64/', '')
EOF
  echo "Built build/packages/$ZIP.zip"
else
  echo "ochenta.exe not found (build it with lazbuild src/ochenta.lpi): no .zip" >&2
fi

[ -x build/linux/ochenta ] || { echo "build/linux/ochenta not found: run build.sh first (no .deb, no .rpm)" >&2; exit 1; }

# The files, staged on a Linux file system (the permissions must be real)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/root"
LIB="$STAGE/usr/lib/ochenta"
mkdir -p "$LIB" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" "$STAGE/usr/share/doc/ochenta"
cp build/linux/ochenta "$LIB/ochenta"
cp -R roms esxdos zxuno "$LIB/"
for F in $NOT_PACKAGED; do rm -f "$LIB/roms/$F"; done
mkdir -p "$LIB/roms/c64"
# The ZX Spectrum Next distribution goes in ~/.config/ochenta/specnext (never packaged)
mkdir -p "$LIB/specnext"
cp README.md LICENSE "$LIB/"
# The native library for host applications, with its documentation
if [ -f build/lib/libochenta.so ]; then
  mkdir -p "$LIB/lib"
  cp build/lib/libochenta.so LIBRARY.md "$LIB/lib/"
fi
# The C# host demo's sources (it is built on Windows)
mkdir -p "$LIB/tests/OchentaHostDemo"
cp tests/csharp/OchentaHostDemo/Ochenta.cs tests/csharp/OchentaHostDemo/Program.cs tests/csharp/OchentaHostDemo/build.bat \
  "$LIB/tests/OchentaHostDemo/"
cp README.md "$STAGE/usr/share/doc/ochenta/"
cp LICENSE "$STAGE/usr/share/doc/ochenta/copyright"
cat > "$STAGE/usr/bin/ochenta" <<'EOF'
#!/bin/sh
exec /usr/lib/ochenta/ochenta "$@"
EOF
cat > "$STAGE/usr/share/applications/ochenta.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ochenta
GenericName=8 bit machines emulator
Comment=$SUMMARY
Exec=ochenta %f
Icon=ochenta
Terminal=false
Categories=Game;Emulator;
MimeType=application/x-spectrum-tap;application/x-spectrum-tzx;application/x-spectrum-z80;application/x-spectrum-sna;
EOF
# The icon: the biggest PNG inside src/ochenta.ico
python3 - src/ochenta.ico "$STAGE/usr/share/icons/hicolor/256x256/apps/ochenta.png" <<'EOF'
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
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$LIB/ochenta" "$STAGE/usr/bin/ochenta"
[ ! -f "$LIB/lib/libochenta.so" ] || chmod 755 "$LIB/lib/libochenta.so"
SIZE=$(du -sk "$STAGE" | cut -f1)

# .deb
if command -v dpkg-deb >/dev/null; then
  mkdir -p "$STAGE/DEBIAN"
  cat > "$STAGE/DEBIAN/control" <<EOF
Package: ochenta
Version: $VERSION
Section: otherosfs
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6, libgtk2.0-0
Recommends: libsdl2-2.0-0
Maintainer: $MAINTAINER
Homepage: https://github.com/Utodev/emu80
Description: $SUMMARY
 ochenta emulates 8 bit machines with a Z80: the ZX Spectrum 16K, 48K, 128K,
 +2, +2B and +3, the ZX-Uno, the ZX Spectrum Next, the Amstrad CPC 464, 664
 and 6128, the SAM Coupe and the MSX2, with exact timing. It loads tapes,
 snapshots, disks and cartridges, and has tape, disk and SD card browsers, a
 Z80 debugger and an adventure debugger for DAAD, PAW and The Quill games.
 Sound needs SDL2.
EOF
  dpkg-deb --root-owner-group --build "$STAGE" "$OUT/ochenta_${VERSION}_amd64.deb" >/dev/null
  rm -rf "$STAGE/DEBIAN"
  echo "Built build/packages/ochenta_${VERSION}_amd64.deb"
else
  echo "dpkg-deb not found: no .deb" >&2
fi

# .rpm
RPMBUILD=${RPMBUILD:-rpmbuild}
if command -v "$(echo "$RPMBUILD" | cut -d' ' -f1)" >/dev/null; then
  mkdir -p "$WORK/rpm/SPECS" "$WORK/rpm/RPMS" "$WORK/rpm/BUILD"
  cat > "$WORK/rpm/SPECS/ochenta.spec" <<EOF
Name: ochenta
Version: $VERSION
Release: 1
Summary: $SUMMARY
License: GPLv3
URL: https://github.com/Utodev/emu80
BuildArch: x86_64
AutoReqProv: no
Requires: gtk2
Recommends: SDL2
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

%description
ochenta emulates 8 bit machines with a Z80: the ZX Spectrum 16K, 48K, 128K,
+2, +2B and +3, the ZX-Uno, the ZX Spectrum Next, the Amstrad CPC 464, 664
and 6128, the SAM Coupe and the MSX2, with exact timing. It loads tapes,
snapshots, disks and cartridges, and has tape, disk and SD card browsers, a
Z80 debugger and an adventure debugger for DAAD, PAW and The Quill games.
Sound needs SDL2.

%install
mkdir -p %{buildroot}
cp -a $STAGE/. %{buildroot}/

%files
%attr(755,root,root) /usr/bin/ochenta
/usr/lib/ochenta
/usr/share/applications/ochenta.desktop
/usr/share/icons/hicolor/256x256/apps/ochenta.png
%doc /usr/share/doc/ochenta
EOF
  $RPMBUILD --quiet -bb --define "_topdir $WORK/rpm" "$WORK/rpm/SPECS/ochenta.spec"
  cp "$WORK/rpm/RPMS/x86_64/ochenta-$VERSION-1.x86_64.rpm" "$OUT/"
  echo "Built build/packages/ochenta-$VERSION-1.x86_64.rpm"
else
  echo "rpmbuild not found (sudo apt install rpm, or dnf install rpm-build): no .rpm" >&2
fi

# .AppImage: the same files as the packages, in an AppDir (it needs appimagetool,
# https://github.com/AppImage/appimagetool; APPIMAGETOOL=path uses one that isn't in the PATH).
# It carries GTK 2 and SDL2 with their libraries (all but the C library and the graphics drivers).
APPIMAGETOOL=${APPIMAGETOOL:-appimagetool}
if command -v "$APPIMAGETOOL" >/dev/null || [ -x "$APPIMAGETOOL" ]; then
  APPDIR="$WORK/ochenta.AppDir"
  mkdir -p "$APPDIR/usr/bin"
  cp -a "$STAGE/usr/lib" "$STAGE/usr/share" "$APPDIR/usr/"
  cp "$STAGE/usr/share/applications/ochenta.desktop" "$APPDIR/ochenta.desktop"
  cp "$STAGE/usr/share/icons/hicolor/256x256/apps/ochenta.png" "$APPDIR/ochenta.png"
  # The libraries it needs (GTK 2 and what GTK needs, and SDL2, which is loaded at run time),
  # all but the C library and the graphics drivers, which must be the system's
  mkdir -p "$APPDIR/usr/lib/bundled"
  SDL=$(PATH="$PATH:/sbin:/usr/sbin" ldconfig -p | sed -n 's/.*libSDL2-2.0.so.0 .*=> //p' | head -1)
  [ -z "$SDL" ] || cp -L "$SDL" "$APPDIR/usr/lib/bundled/"
  for F in build/linux/ochenta $SDL; do
    ldd "$F" | awk '/=> \// {print $3}'
  done | sort -u | grep -v -E '/(ld-linux[^/]*|libc|libm|libdl|libpthread|librt|libresolv|libutil|libnsl|libGL|libGLX|libGLdispatch|libEGL|libdrm|libgbm)\.so' |
  while read -r L; do cp -L "$L" "$APPDIR/usr/lib/bundled/"; done
  # gdk-pixbuf's image loaders, with a loaders.cache AppRun points at the AppDir
  PIXDIR=$(dirname "$(find /usr/lib /lib -path '*gdk-pixbuf-2.0/2.10.0/loaders.cache' 2>/dev/null | head -1)")
  if [ -d "$PIXDIR/loaders" ]; then
    mkdir -p "$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0"
    cp -R "$PIXDIR/loaders" "$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/"
    sed "s|$PIXDIR/loaders|@APPDIR@/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders|" "$PIXDIR/loaders.cache" \
      > "$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache.in"
  fi
  cat > "$APPDIR/AppRun" <<'EOS'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$HERE/usr/lib/bundled${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
CACHE="$HERE/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache.in"
if [ -f "$CACHE" ]; then
  OUT="${XDG_RUNTIME_DIR:-/tmp}/ochenta-pixbuf-$(id -u).cache"
  sed "s|@APPDIR@|$HERE|g" "$CACHE" > "$OUT" && export GDK_PIXBUF_MODULE_FILE="$OUT"
fi
# GTK's own plug-ins (input methods, accessibility) are the system's, built for its GTK
export GTK_MODULES= GTK_IM_MODULE=gtk-im-context-simple
exec "$HERE/usr/lib/ochenta/ochenta" "$@"
EOS
  chmod 755 "$APPDIR/AppRun"
  # appimagetool is itself an AppImage: --appimage-extract-and-run works without FUSE
  rm -f "$OUT/ochenta-$VERSION-x86_64.AppImage"
  ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$APPDIR" "$OUT/ochenta-$VERSION-x86_64.AppImage" >"$WORK/appimagetool.log" 2>&1 \
    && echo "Built build/packages/ochenta-$VERSION-x86_64.AppImage" \
    || { tail -5 "$WORK/appimagetool.log" >&2; echo "appimagetool failed: no .AppImage" >&2; }
else
  echo "appimagetool not found (https://github.com/AppImage/appimagetool/releases): no .AppImage" >&2
fi
