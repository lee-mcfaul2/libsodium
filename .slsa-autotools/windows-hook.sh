#!/bin/bash
#
# slsa-autotools Windows build hook for libsodium.
#
# Cross-compiles libsodium for Windows (x86_64 and i686) via mingw-w64
# and packages both architectures into a single archive named
# ${PACKAGE}-${VERSION}-windows.tar.gz, which the slsa-autotools
# build_windows job picks up via its standard glob.
#
# Implementation note. We do *not* invoke libsodium's upstream
# dist-build/msys2-{win64,win32}.sh scripts directly — those scripts
# end with `make check && make install`, and `make check` runs the
# cross-compiled .exe test binaries. On a real MSYS2 host those .exe
# files run natively; on a plain Linux runner (where slsa-autotools
# operates) they cannot run without wine, so every test fails, the
# `&&` chain breaks before `make install`, and no build tree is
# produced. Replicating the relevant configure flags + `make` +
# `make install` ourselves sidesteps the problem cleanly without
# touching the upstream scripts. CFLAGS values are copied verbatim
# from the upstream scripts so the produced binaries match what
# upstream would emit.
#
# Invoked by .github/workflows/release.yml's build_windows job from
# inside a freshly-generated distdir. The /opt/wrappers/${triplet}-gcc
# on PATH intercepts the mingw compiler invocations so that
# -ffile-prefix-map, -Wl,--no-insert-timestamp, and
# -Wl,--build-id=none take effect — the scaffolder's reproducibility
# wrappers do not need to know anything project-specific.

set -euo pipefail

# Read PACKAGE + VERSION from configure.ac. The Makefile-based
# extraction used elsewhere in the pipeline does not work here: the
# hook runs from inside a fresh distdir where ./configure has not
# been run yet (build_arch below invokes ./configure once per arch).
# libsodium's AC_INIT is single-line:
#   AC_INIT([libsodium],[1.0.23],[bug@...],[libsodium],[https://...])
# Field 2 of a [ / ] split is PACKAGE, field 4 is VERSION.
read -r PACKAGE VERSION < <(
  awk 'BEGIN{FS="[][]"} /^AC_INIT/ {print $2, $4; exit}' configure.ac
)
[ -n "${PACKAGE}" ] && [ -n "${VERSION}" ] || {
  echo "ERROR: could not extract PACKAGE/VERSION from configure.ac" >&2
  exit 1
}

build_arch() {
  local host="$1" prefix="$2" cflags="$3"

  # Re-prepare the source tree for this arch's configure run. After
  # the first build, ./configure cache + make output are tied to the
  # previous --host; distclean throws all of that away so the next
  # configure starts from scratch. First invocation has no prior
  # state, so distclean is allowed to fail silently.
  make distclean >/dev/null 2>&1 || true

  CFLAGS="${cflags}" ./configure --quiet \
    --prefix="${prefix}" --exec-prefix="${prefix}" \
    --host="${host}"

  make -s
  make -s install
}

build_arch "x86_64-w64-mingw32" "$(pwd)/libsodium-win64" \
  "-O3 -fomit-frame-pointer -m64 -mtune=westmere"

build_arch "i686-w64-mingw32" "$(pwd)/libsodium-win32" \
  "-O3 -fomit-frame-pointer -m32 -march=pentium3 -mtune=westmere"

ARCHIVE_STEM="${PACKAGE}-${VERSION}-windows"

tar --owner=0 --group=0 --numeric-owner \
    --mode='u+rw,go+r-w' --sort=name \
    --clamp-mtime --mtime="@${SOURCE_DATE_EPOCH}" \
    -cf "${ARCHIVE_STEM}.tar" \
    libsodium-win64 libsodium-win32

gzip -c --no-name --best "${ARCHIVE_STEM}.tar" \
  > "${ARCHIVE_STEM}.tar.gz"

rm -f "${ARCHIVE_STEM}.tar"

ls -la "${ARCHIVE_STEM}.tar.gz"
