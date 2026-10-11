#!/bin/bash
# Linux build used by .github/workflows/linux.yml.
# Jam comes from the distro package (Perforce Jam or FTJam). Boost Jam is rejected.
set -euxo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
: "${PREFIX:=$ROOT/.prefix}"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  autoconf \
  build-essential \
  gettext \
  pkg-config \
  jam \
  libfltk1.3-dev \
  libx11-dev \
  libxext-dev \
  libxft-dev \
  libxinerama-dev \
  libxrender-dev \
  libxrandr-dev \
  libxcomposite-dev \
  libxdamage-dev \
  libxfixes-dev \
  libxpm-dev \
  libxkbfile-dev \
  libpng-dev \
  libjpeg-dev \
  libfontconfig1-dev \
  libfreetype6-dev \
  libdbus-1-dev \
  libstartup-notification0-dev \
  libcurl4-openssl-dev

command -v jam
jam -v
if jam -v 2>&1 | grep -Eiq 'boost|Boost\.Jam'; then
  echo "Boost Jam cannot build EDE. Install the Perforce 'jam' package, not b2."
  exit 1
fi

# -f replaces the built-in Jambase. Echo prints JAMVERSION during parse, then
# Jam exits 1 because it still tries to build. m4/jam.m4 ignores that status.
printf 'Echo $(JAMVERSION) ;\n' > /tmp/conftest.jam
jam -f /tmp/conftest.jam > /tmp/jamver.out 2>/tmp/jamver.err || true
jam_version_orig=$(head -1 /tmp/jamver.out || true)
jam_version_orig=${jam_version_orig//[[:space:]]/}
jam_version=${jam_version_orig//./}
echo "JAMVERSION=$jam_version_orig (numeric $jam_version)"
case "$jam_version" in
  ''|*[!0-9]*)
    echo "configure requires a numeric Jam version (vanilla Jam or FTJam). Got: '$jam_version_orig'"
    echo "---- jam stdout ----"
    cat /tmp/jamver.out || true
    echo "---- jam stderr ----"
    cat /tmp/jamver.err || true
    exit 1
    ;;
esac
if [ "$jam_version" -lt 23 ]; then
  echo "Jam $jam_version_orig is older than 2.3"
  exit 1
fi
fltk-config --version

cd "$ROOT/external/edelib"
./autogen.sh
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" --enable-debug
# Do not run plain `jam install`: it also builds tests and examples, which
# fail to link (undefined edelib::* symbols). It can also silently skip
# targets ("don't know how to make ...") while still installing pkg-config
# files, so we explicitly build every artifact EDE needs, then install.
for t in lib/libedelib.a lib/libedelib_gui.a lib/libedelib_dbus.a; do
  if jam -j"$(nproc)" "$t"; then
    continue
  fi
  # libedelib_dbus.a is only defined when configure detected D-Bus.
  case "$t" in
    *dbus*) echo "warning: skipping $t (not built by this configuration)" ;;
    *) exit 1 ;;
  esac
done
jam -j"$(nproc)" install
test -f "${PREFIX}/lib/libedelib.a"
test -f "${PREFIX}/lib/libedelib_gui.a"
test -f "${PREFIX}/lib/pkgconfig/edelib.pc"
test -f "${PREFIX}/lib/pkgconfig/edelib-gui.pc"

cd "$ROOT"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
./autogen.sh
./configure --prefix="${PREFIX}" --enable-debug --with-edelib-path="${PREFIX}"
# Doc rules call asciidoc whenever PYTHON is set. This job checks
# that the desktop compiles; it does not install asciidoc.
sed -i 's/^PYTHON.*/PYTHON = ;/' Jamconfig
jam -j"$(nproc)"
jam install
find "${PREFIX}/bin" -maxdepth 1 -type f -printf '%f\n' | sort
