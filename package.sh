#!/bin/sh
# Makes .deb and .rpm packages of the Linux build (run build.sh first) and
# a .zip of the Windows one (pzx.exe in this folder, built with lazbuild).
#
#   ./package.sh            the packages, into build/packages/
#
# The .zip has a pzx-VERSION-windows folder with pzx.exe, roms, esxdos,
# zxuno, README.md and LICENSE (pzx.ini is made there when pzx closes), and a
# lib folder with the native library for host applications (pzxlib.dll) and
# its documentation (LIBRARY.md), and a tests folder with the C# host demo
# (tests/csharp/PzxHostDemo: its sources, build.bat and, in the .zip, the
# program built, which runs with --selftest). The library is built, if it
# isn't there, with src/lib/build-lib.sh.
# The .deb needs dpkg-deb (Debian, Ubuntu); the .rpm needs rpmbuild
# (Debian/Ubuntu: sudo apt install rpm; Fedora: sudo dnf install rpm-build).
# RPMBUILD=command uses another rpmbuild.
#
# Installed layout: the program, roms, esxdos, zxuno, README.md and LICENSE
# in /usr/lib/pzx (pzx finds them next to itself), and its lib folder with
# libpzxlib.so and LIBRARY.md, and its tests folder with the C# demo's sources, /usr/bin/pzx to start it,
# a desktop entry and the icon. The settings go to ~/.config/pzx/pzx.ini,
# as /usr/lib/pzx can't be written. The version is the release number
# (src/Release.inc). Sound needs SDL2, recommended by both packages.
set -e
cd "$(dirname "$0")"
ROOT=$(pwd)

VERSION=$(sed -n "s/.*PZX_RELEASE = '\([0-9]*\)'.*/\1/p" src/Release.inc)
[ -n "$VERSION" ] || { echo "No release number in src/Release.inc" >&2; exit 1; }
MAINTAINER="Uto <csanchez@kioskoymas.com>"
SUMMARY="ZX Spectrum emulator (48K, 128K, +2, +2B, +3, ZX-Uno)"
OUT="$ROOT/build/packages"
mkdir -p "$OUT"

# The native library, for the packages' lib folder (built here if needed)
if [ ! -f build/lib/pzxlib.dll ]; then
  src/lib/build-lib.sh >/dev/null 2>&1 || echo "Could not build pzxlib.dll: the .zip has no lib folder" >&2
fi
if [ ! -f build/lib/libpzxlib.so ]; then
  src/lib/build-lib.sh linux >/dev/null 2>&1 || echo "Could not build libpzxlib.so: no lib folder in the .deb and .rpm" >&2
fi

# The C# host demo, built (Windows only) for the .zip
DEMO=tests/csharp/PzxHostDemo
if [ -f build/lib/pzxlib.dll ] && command -v cmd.exe >/dev/null; then
  (cd "$DEMO" && cmd.exe /c build.bat >/dev/null 2>&1) || echo "Could not build the C# demo: the .zip has its sources only" >&2
fi

# Windows: a .zip of pzx.exe and its folders
if [ -f pzx.exe ]; then
  ZIP="pzx-$VERSION-windows"
  rm -f "$OUT/$ZIP.zip"
  python3 - "$OUT/$ZIP.zip" "$ZIP" pzx.exe roms esxdos zxuno README.md LICENSE <<'EOF'
import os, sys, zipfile
out, top, names = sys.argv[1], sys.argv[2], sys.argv[3:]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in names:
        if os.path.isdir(name):
            for folder, dirs, files in os.walk(name):
                dirs.sort()
                for f in sorted(files):
                    path = os.path.join(folder, f)
                    z.write(path, os.path.join(top, path))
        else:
            z.write(name, os.path.join(top, name))
    # The native library and its documentation
    if os.path.exists('build/lib/pzxlib.dll'):
        z.write('build/lib/pzxlib.dll', top + '/lib/pzxlib.dll')
        z.write('LIBRARY.md', top + '/lib/LIBRARY.md')
    # The C# host demo: sources, build.bat, and the program built if it is
    for f in ('Pzx.cs', 'Program.cs', 'build.bat'):
        z.write('tests/csharp/PzxHostDemo/' + f, top + '/tests/PzxHostDemo/' + f)
    if os.path.exists('build/csharp/PzxHostDemo.exe') and os.path.exists('build/lib/pzxlib.dll'):
        z.write('build/csharp/PzxHostDemo.exe', top + '/tests/PzxHostDemo/PzxHostDemo.exe')
        z.write('build/lib/pzxlib.dll', top + '/tests/PzxHostDemo/pzxlib.dll')
    # The empty folder for the ZX Spectrum Next distribution (never its contents)
    z.writestr(top + '/specnext/', '')
EOF
  echo "Built build/packages/$ZIP.zip"
else
  echo "pzx.exe not found (build it with lazbuild src/pzx.lpi): no .zip" >&2
fi

[ -x build/linux/pzx ] || { echo "build/linux/pzx not found: run build.sh first (no .deb, no .rpm)" >&2; exit 1; }

# The files, staged on a Linux file system (the permissions must be real)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/root"
LIB="$STAGE/usr/lib/pzx"
mkdir -p "$LIB" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" "$STAGE/usr/share/doc/pzx"
cp build/linux/pzx "$LIB/pzx"
cp -R roms esxdos zxuno "$LIB/"
# The ZX Spectrum Next distribution goes in ~/.config/pzx/specnext (never packaged)
mkdir -p "$LIB/specnext"
cp README.md LICENSE "$LIB/"
# The native library for host applications, with its documentation
if [ -f build/lib/libpzxlib.so ]; then
  mkdir -p "$LIB/lib"
  cp build/lib/libpzxlib.so LIBRARY.md "$LIB/lib/"
fi
# The C# host demo's sources (it is built on Windows)
mkdir -p "$LIB/tests/PzxHostDemo"
cp tests/csharp/PzxHostDemo/Pzx.cs tests/csharp/PzxHostDemo/Program.cs tests/csharp/PzxHostDemo/build.bat \
  "$LIB/tests/PzxHostDemo/"
cp README.md "$STAGE/usr/share/doc/pzx/"
cp LICENSE "$STAGE/usr/share/doc/pzx/copyright"
cat > "$STAGE/usr/bin/pzx" <<'EOF'
#!/bin/sh
exec /usr/lib/pzx/pzx "$@"
EOF
cat > "$STAGE/usr/share/applications/pzx.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=pzx
GenericName=ZX Spectrum emulator
Comment=$SUMMARY
Exec=pzx %f
Icon=pzx
Terminal=false
Categories=Game;Emulator;
MimeType=application/x-spectrum-tap;application/x-spectrum-tzx;application/x-spectrum-z80;application/x-spectrum-sna;
EOF
# The icon: the biggest PNG inside src/pzx.ico
python3 - src/pzx.ico "$STAGE/usr/share/icons/hicolor/256x256/apps/pzx.png" <<'EOF'
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
chmod 755 "$LIB/pzx" "$STAGE/usr/bin/pzx"
[ ! -f "$LIB/lib/libpzxlib.so" ] || chmod 755 "$LIB/lib/libpzxlib.so"
SIZE=$(du -sk "$STAGE" | cut -f1)

# .deb
if command -v dpkg-deb >/dev/null; then
  mkdir -p "$STAGE/DEBIAN"
  cat > "$STAGE/DEBIAN/control" <<EOF
Package: pzx
Version: $VERSION
Section: otherosfs
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6, libgtk2.0-0
Recommends: libsdl2-2.0-0
Maintainer: $MAINTAINER
Homepage: https://github.com/Utodev/pzx
Description: $SUMMARY
 pzx (Pascal ZX) emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3
 and the ZX-Uno with exact timing, loads TAP, TZX, SNA, Z80 and DSK files,
 and has a tape browser, disk and SD card browsers (DivMMC with esxDOS), a
 Z80 debugger and an adventure debugger for DAAD, PAW and The Quill games.
 Sound needs SDL2.
EOF
  dpkg-deb --root-owner-group --build "$STAGE" "$OUT/pzx_${VERSION}_amd64.deb" >/dev/null
  rm -rf "$STAGE/DEBIAN"
  echo "Built build/packages/pzx_${VERSION}_amd64.deb"
else
  echo "dpkg-deb not found: no .deb" >&2
fi

# .rpm
RPMBUILD=${RPMBUILD:-rpmbuild}
if command -v "$(echo "$RPMBUILD" | cut -d' ' -f1)" >/dev/null; then
  mkdir -p "$WORK/rpm/SPECS" "$WORK/rpm/RPMS" "$WORK/rpm/BUILD"
  cat > "$WORK/rpm/SPECS/pzx.spec" <<EOF
Name: pzx
Version: $VERSION
Release: 1
Summary: $SUMMARY
License: GPLv3
URL: https://github.com/Utodev/pzx
BuildArch: x86_64
AutoReqProv: no
Requires: gtk2
Recommends: SDL2
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

%description
pzx (Pascal ZX) emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3
and the ZX-Uno with exact timing, loads TAP, TZX, SNA, Z80 and DSK files,
and has a tape browser, disk and SD card browsers (DivMMC with esxDOS), a
Z80 debugger and an adventure debugger for DAAD, PAW and The Quill games.
Sound needs SDL2.

%install
mkdir -p %{buildroot}
cp -a $STAGE/. %{buildroot}/

%files
%attr(755,root,root) /usr/bin/pzx
/usr/lib/pzx
/usr/share/applications/pzx.desktop
/usr/share/icons/hicolor/256x256/apps/pzx.png
%doc /usr/share/doc/pzx
EOF
  $RPMBUILD --quiet -bb --define "_topdir $WORK/rpm" "$WORK/rpm/SPECS/pzx.spec"
  cp "$WORK/rpm/RPMS/x86_64/pzx-$VERSION-1.x86_64.rpm" "$OUT/"
  echo "Built build/packages/pzx-$VERSION-1.x86_64.rpm"
else
  echo "rpmbuild not found (sudo apt install rpm, or dnf install rpm-build): no .rpm" >&2
fi
