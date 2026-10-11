#!/bin/bash
# Linux build used by .github/workflows/linux.yml.
# Jam comes from the distro package (Perforce Jam or FTJam). Boost Jam is rejected.
set -euxo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
: "${PREFIX:=$ROOT/.prefix}"

# When the actions/cache step restored a complete edelib installation,
# skip the whole edelib build. The key includes the exact submodule
# commit and linux.sh, so a hit means these artifacts were produced by
# this same script on this same source revision. Verify the critical
# files exist before trusting the cache; if anything is missing we fall
# through to a normal (incremental) build below.
if test -f "${PREFIX}/lib/libedelib.a" \
   && test -f "${PREFIX}/lib/libedelib_gui.a" \
   && test -f "${PREFIX}/lib/pkgconfig/edelib.pc" \
   && test -f "${PREFIX}/lib/pkgconfig/edelib-gui.pc"; then
  echo "::notice::edelib found in cache (${PREFIX}); skipping autogen/configure/jam install."
  EDELIB_CACHED=yes
else
  EDELIB_CACHED=no
fi

if [ "$EDELIB_CACHED" = no ]; then
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

# Toolchain checks (jam version, fltk-config) only matter when we are
# about to compile; on a full cache hit they are skipped as well.
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

# Trim edelib's top-level Jamfile so 'jam install' builds ONLY what EDE
# needs: the library headers/sources (edelib, src, sslib) and the pkg-config
# files (pc). The other sub-includes (test, examples, doc, tools, po) drag
# in programs/tests/docs/locale that fail to link or require extra host
# tools, and they also trigger a Jam scoping quirk where install targets
# resolve against the wrong project scope ("don't know how to make ...").
# Commenting those SubInclude lines is done with sed right here instead of
# patching the upstream submodule, keeping the PR diff minimal. A grep
# guard makes the step idempotent and fails loudly if the Jamfile layout
# ever changes so this patch stops applying silently.
for d in test examples doc tools po; do
  grep -q "^SubInclude TOP ${d} ;$" Jamfile || {
    echo "error: unexpected edelib Jamfile layout (no active SubInclude TOP ${d})" >&2
    exit 1
  }
  sed -i "s|^SubInclude TOP ${d} ;|#SubInclude TOP ${d} ;|" Jamfile
done

./autogen.sh
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" --enable-debug

# Build the libraries explicitly first. Even with the trimmed Jamfile,
# a clean tree needs the archive targets materialised before the install
# pass can copy them into ${PREFIX}; each name is conditional because
# optional components (dbus) depend on what configure detected.
for t in lib/libedelib.a lib/libedelib_gui.a lib/libedelib_dbus.a; do
  if ! jam -q -j"$(nproc)" "$t"; then
    echo "warning: target '$t' not buildable in this configuration, skipping"
  fi
done

# -q makes Jam stop on the first error, so 'jam install' now fails loudly
# if anything required is missing (the old script had to re-run install and
# hand-verify artifacts because silent skips were possible).
jam -q -j"$(nproc)" install

# Fail loudly if anything important was skipped or missing.
test -f "${PREFIX}/lib/libedelib.a"
test -f "${PREFIX}/lib/libedelib_gui.a"
test -f "${PREFIX}/lib/pkgconfig/edelib.pc"
test -f "${PREFIX}/lib/pkgconfig/edelib-gui.pc"
if [ -f pc/edelib-dbus.pc ]; then
  test -f "${PREFIX}/lib/libedelib_dbus.a"
  test -f "${PREFIX}/lib/pkgconfig/edelib-dbus.pc"
fi
fi   # end of: if [ "$EDELIB_CACHED" = no ]

cd "$ROOT"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Guard against broken pkg-config files: if an edelib revision ships .pc
# templates containing 'libdir=${libdir}' (a variable that is never defined
# inside a pkg-config file), 'pkg-config --libs edelib' emits a bare '-L'
# with no argument. EDE's configure copies those flags into Jamconfig
# verbatim and every link then fails with "cannot find -ledelib". The
# submodule pin (external/edelib) includes the upstream fix, so normally
# nothing needs rewriting here; we only repair installed .pc files if the
# broken pattern ever reappears, and fail loudly if it cannot be repaired.
for pc in "${PREFIX}"/lib/pkgconfig/edelib*.pc; do
  [ -f "$pc" ] || continue
  grep -q '^libdir=${libdir}$' "$pc" || continue
  echo "warning: $pc has an undefined libdir variable; repairing in place" >&2
  sed -i \
    -e 's|^\(libdir=\)${libdir}$|\1${exec_prefix}/lib|' \
    -e 's|^\(includedir=\)${includedir}$|\1${prefix}/include|' \
    "$pc"
done
# Sanity check: pkg-config must not emit an argument-less -L.
if pkg-config --libs edelib | grep -qE '(^| )-L( |$)'; then
  echo "error: edelib pkg-config files produce a bare -L flag" >&2
  pkg-config --libs edelib >&2
  exit 1
fi

./autogen.sh
./configure --prefix="${PREFIX}" --enable-debug --with-edelib-path="${PREFIX}"
# Doc rules call asciidoc whenever PYTHON is set. This job checks
# that the desktop compiles; it does not install asciidoc.
sed -i 's/^PYTHON.*/PYTHON = ;/' Jamconfig

# Another upstream quirk: ede-calc calls exp()/pow() but its link line
# (FLTK + libstdc++) has no libm, so linking fails on modern glibc with
# "undefined reference to symbol 'exp@@GLIBC_2.29'" ("DSO missing from
# command line"). Patch the Jamfile of every program that uses math
# functions to append -lm explicitly. Use jam's "+=" operator: per-target
# assignment with $(VAR) self-reference does not expand reliably here,
# but "+=" appends to whatever the rule set for the target.
for d in ede-calc; do
  sed -i -E "s|^(FltkProgramBare ${d} : .*)\$|\1\nLINKLIBS on ${d} += -lm ;|" "$d/Jamfile"
done

jam -j"$(nproc)"
jam install

# Verify the programs that need extra libraries really linked: the binary
# must exist and be dynamically linked against libm.
test -x "${PREFIX}/bin/ede-calc"
ldd "${PREFIX}/bin/ede-calc" | grep -q 'libm\.so'

find "${PREFIX}/bin" -maxdepth 1 -type f -printf '%f\n' | sort
