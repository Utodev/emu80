#!/bin/sh
# Makes .deb and .rpm packages of the Linux build (run build.sh first) and
# a .zip of the Windows one (emu80.exe in this folder, built with lazbuild).
#
#   ./package.sh            the packages, into build/packages/
#
# The .zip has an emu80-VERSION-windows folder with emu80.exe, roms, esxdos,
# zxuno, README.md and LICENSE (emu80.ini is made there when emu80 closes), and a
# lib folder with the native library for host applications (e80lib.dll) and
# its documentation (LIBRARY.md), and a tests folder with the C# host demo
# (tests/csharp/Emu80HostDemo: its sources, build.bat and, in the .zip, the
# program built, which runs with --selftest). The library is built, if it
# isn't there, with src/lib/build-lib.sh.
# The .deb needs dpkg-deb (Debian, Ubuntu); the .rpm needs rpmbuild
# (Debian/Ubuntu: sudo apt install rpm; Fedora: sudo dnf install rpm-build).
# RPMBUILD=command uses another rpmbuild.
#
# Installed layout: the program, roms, esxdos, zxuno, README.md and LICENSE
# in /usr/lib/emu80 (emu80 finds them next to itself), and its lib folder with
# libe80.so and LIBRARY.md, and its tests folder with the C# demo's sources, /usr/bin/emu80 to start it,
# a desktop entry and the icon. The settings go to ~/.config/emu80/emu80.ini,
# as /usr/lib/emu80 can't be written. The version is the release number
# (src/Release.inc). Sound needs SDL2, recommended by both packages.
set -e
cd "$(dirname "$0")"
ROOT=$(pwd)

VERSION=$(sed -n "s/.*EMU80_RELEASE = '\([0-9]*\)'.*/\1/p" src/Release.inc)
[ -n "$VERSION" ] || { echo "No release number in src/Release.inc" >&2; exit 1; }
MAINTAINER="Uto <csanchez@kioskoymas.com>"
SUMMARY="ZX Spectrum emulator (48K, 128K, +2, +2B, +3, ZX-Uno)"
OUT="$ROOT/build/packages"
mkdir -p "$OUT"

# The native library, for the packages' lib folder (built here if needed)
if [ ! -f build/lib/e80lib.dll ]; then
  src/lib/build-lib.sh >/dev/null 2>&1 || echo "Could not build e80lib.dll: the .zip has no lib folder" >&2
fi
if [ ! -f build/lib/libe80.so ]; then
  src/lib/build-lib.sh linux >/dev/null 2>&1 || echo "Could not build libe80.so: no lib folder in the .deb and .rpm" >&2
fi

# The C# host demo, built (Windows only) for the .zip
DEMO=tests/csharp/Emu80HostDemo
if [ -f build/lib/e80lib.dll ] && command -v cmd.exe >/dev/null; then
  (cd "$DEMO" && cmd.exe /c build.bat >/dev/null 2>&1) || echo "Could not build the C# demo: the .zip has its sources only" >&2
fi

# Windows: a .zip of emu80.exe and its folders
if [ -f emu80.exe ]; then
  ZIP="emu80-$VERSION-windows"
  rm -f "$OUT/$ZIP.zip"
  python3 - "$OUT/$ZIP.zip" "$ZIP" emu80.exe roms esxdos zxuno README.md LICENSE <<'EOF'
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
    if os.path.exists('build/lib/e80lib.dll'):
        z.write('build/lib/e80lib.dll', top + '/lib/e80lib.dll')
        z.write('LIBRARY.md', top + '/lib/LIBRARY.md')
    # The C# host demo: sources, build.bat, and the program built if it is
    for f in ('Emu80.cs', 'Program.cs', 'build.bat'):
        z.write('tests/csharp/Emu80HostDemo/' + f, top + '/tests/Emu80HostDemo/' + f)
    if os.path.exists('build/csharp/Emu80HostDemo.exe') and os.path.exists('build/lib/e80lib.dll'):
        z.write('build/csharp/Emu80HostDemo.exe', top + '/tests/Emu80HostDemo/Emu80HostDemo.exe')
        z.write('build/lib/e80lib.dll', top + '/tests/Emu80HostDemo/e80lib.dll')
    # The empty folder for the ZX Spectrum Next distribution (never its contents)
    z.writestr(top + '/specnext/', '')
EOF
  echo "Built build/packages/$ZIP.zip"
else
  echo "emu80.exe not found (build it with lazbuild src/emu80.lpi): no .zip" >&2
fi

[ -x build/linux/emu80 ] || { echo "build/linux/emu80 not found: run build.sh first (no .deb, no .rpm)" >&2; exit 1; }

# The files, staged on a Linux file system (the permissions must be real)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/root"
LIB="$STAGE/usr/lib/emu80"
mkdir -p "$LIB" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" "$STAGE/usr/share/doc/emu80"
cp build/linux/emu80 "$LIB/emu80"
cp -R roms esxdos zxuno "$LIB/"
# The ZX Spectrum Next distribution goes in ~/.config/emu80/specnext (never packaged)
mkdir -p "$LIB/specnext"
cp README.md LICENSE "$LIB/"
# The native library for host applications, with its documentation
if [ -f build/lib/libe80.so ]; then
  mkdir -p "$LIB/lib"
  cp build/lib/libe80.so LIBRARY.md "$LIB/lib/"
fi
# The C# host demo's sources (it is built on Windows)
mkdir -p "$LIB/tests/Emu80HostDemo"
cp tests/csharp/Emu80HostDemo/Emu80.cs tests/csharp/Emu80HostDemo/Program.cs tests/csharp/Emu80HostDemo/build.bat \
  "$LIB/tests/Emu80HostDemo/"
cp README.md "$STAGE/usr/share/doc/emu80/"
cp LICENSE "$STAGE/usr/share/doc/emu80/copyright"
cat > "$STAGE/usr/bin/emu80" <<'EOF'
#!/bin/sh
exec /usr/lib/emu80/emu80 "$@"
EOF
cat > "$STAGE/usr/share/applications/emu80.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=emu80
GenericName=ZX Spectrum emulator
Comment=$SUMMARY
Exec=emu80 %f
Icon=emu80
Terminal=false
Categories=Game;Emulator;
MimeType=application/x-spectrum-tap;application/x-spectrum-tzx;application/x-spectrum-z80;application/x-spectrum-sna;
EOF
# The icon: the biggest PNG inside src/emu80.ico
python3 - src/emu80.ico "$STAGE/usr/share/icons/hicolor/256x256/apps/emu80.png" <<'EOF'
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
chmod 755 "$LIB/emu80" "$STAGE/usr/bin/emu80"
[ ! -f "$LIB/lib/libe80.so" ] || chmod 755 "$LIB/lib/libe80.so"
SIZE=$(du -sk "$STAGE" | cut -f1)

# .deb
if command -v dpkg-deb >/dev/null; then
  mkdir -p "$STAGE/DEBIAN"
  cat > "$STAGE/DEBIAN/control" <<EOF
Package: emu80
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
 emu80 (Pascal ZX) emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3
 and the ZX-Uno with exact timing, loads TAP, TZX, SNA, Z80 and DSK files,
 and has a tape browser, disk and SD card browsers (DivMMC with esxDOS), a
 Z80 debugger and an adventure debugger for DAAD, PAW and The Quill games.
 Sound needs SDL2.
EOF
  dpkg-deb --root-owner-group --build "$STAGE" "$OUT/emu80_${VERSION}_amd64.deb" >/dev/null
  rm -rf "$STAGE/DEBIAN"
  echo "Built build/packages/emu80_${VERSION}_amd64.deb"
else
  echo "dpkg-deb not found: no .deb" >&2
fi

# .rpm
RPMBUILD=${RPMBUILD:-rpmbuild}
if command -v "$(echo "$RPMBUILD" | cut -d' ' -f1)" >/dev/null; then
  mkdir -p "$WORK/rpm/SPECS" "$WORK/rpm/RPMS" "$WORK/rpm/BUILD"
  cat > "$WORK/rpm/SPECS/emu80.spec" <<EOF
Name: emu80
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
emu80 (Pascal ZX) emulates the ZX Spectrum 16K, 48K, 128K, +2, +2B and +3
and the ZX-Uno with exact timing, loads TAP, TZX, SNA, Z80 and DSK files,
and has a tape browser, disk and SD card browsers (DivMMC with esxDOS), a
Z80 debugger and an adventure debugger for DAAD, PAW and The Quill games.
Sound needs SDL2.

%install
mkdir -p %{buildroot}
cp -a $STAGE/. %{buildroot}/

%files
%attr(755,root,root) /usr/bin/emu80
/usr/lib/emu80
/usr/share/applications/emu80.desktop
/usr/share/icons/hicolor/256x256/apps/emu80.png
%doc /usr/share/doc/emu80
EOF
  $RPMBUILD --quiet -bb --define "_topdir $WORK/rpm" "$WORK/rpm/SPECS/emu80.spec"
  cp "$WORK/rpm/RPMS/x86_64/emu80-$VERSION-1.x86_64.rpm" "$OUT/"
  echo "Built build/packages/emu80-$VERSION-1.x86_64.rpm"
else
  echo "rpmbuild not found (sudo apt install rpm, or dnf install rpm-build): no .rpm" >&2
fi
