#!/bin/bash
#
# slsa-autotools Windows build hook for libsodium.
#
# Wraps libsodium's upstream mingw cross-compile scripts
# (dist-build/msys2-win64.sh and msys2-win32.sh) into the single-
# archive shape slsa-autotools' build_windows job expects: one file
# named ${PACKAGE}-${VERSION}-windows.tar.gz sitting in CWD when the
# hook returns.
#
# Invoked by .github/workflows/release.yml's build_windows job from
# inside a freshly-generated distdir. The /opt/wrappers/${triplet}-gcc
# on PATH intercepts the mingw compiler invocations so that
# -ffile-prefix-map, -Wl,--no-insert-timestamp, and
# -Wl,--build-id=none take effect — the upstream scripts themselves
# stay unmodified.

set -euo pipefail

# 1. 64-bit build. The script writes its install tree into
#    ./libsodium-win64 via --prefix=$PWD/libsodium-win64.
bash dist-build/msys2-win64.sh

# 2. 32-bit build. msys2-win32.sh does its own `make clean` before
#    rebuilding, so running it after win64 is safe — it doesn't
#    clobber the libsodium-win64/ install tree, only the object
#    files in the source tree.
bash dist-build/msys2-win32.sh

# 3. Derive PACKAGE and VERSION from the generated Makefile (same
#    mechanism used by build_source elsewhere in release.yml).
PACKAGE=$(awk -F' *= *' '$1 == "PACKAGE" {print $2; exit}' Makefile)
VERSION=$(awk -F' *= *' '$1 == "VERSION" {print $2; exit}' Makefile)

# 4. Package both architectures into a single tarball. Using
#    ${PACKAGE}-${VERSION}-windows.tar.gz so build_windows' output
#    glob (`*-windows.{zip,7z,tar.gz,tar.xz}`) picks it up. This
#    diverges slightly from upstream's naming (which uses -mingw);
#    if you'd rather match upstream exactly, rename here and broaden
#    the glob in release.yml.
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
