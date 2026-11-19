#!/bin/sh
# Prepares a Ladybird tree for a build against system libraries.
#
# Ladybird's build system expects the third-party libraries that its vcpkg
# ports install, and the names of some of them differ from the ones the
# system libraries have. This script makes those changes, so that the tree can
# be configured with CMake without vcpkg.
#
# It is idempotent, and it only changes files that the changes apply to.
#
# Usage: nix run .#prepare-tree [directory]

set -eu

directory="${1:-.}"
pdfjs="${PDFJS_DIR:-}"

if [ ! -f "$directory/Meta/CMake/check_for_dependencies.cmake" ]; then
    echo "prepare-tree: $directory does not look like a Ladybird tree" >&2
    exit 1
fi

cd "$directory"

# Upstream suffixes its reduced FFmpeg build to coexist with a system FFmpeg.
# The system libraries have no such suffix.
sed -i \
    -e 's/libavcodec-ladybird/libavcodec/g' \
    -e 's/libavutil-ladybird/libavutil/g' \
    -e 's/libswresample-ladybird/libswresample/g' \
    Meta/CMake/check_for_dependencies.cmake

# Newer Rust compilers emit deprecation warnings that -Dwarnings turns into
# errors.
sed -i 's/set(RUSTC_TARGET_FLAGS -Dwarnings /set(RUSTC_TARGET_FLAGS /' \
    Meta/CMake/rust_crate.cmake

# The PDF.js viewer has to be patched to load from Ladybird's resource URLs.
# Without it, the browser has no PDF viewer.
if [ -n "$pdfjs" ] && [ -d "$pdfjs" ]; then
    if [ ! -f pdfjs/build/pdf.mjs ]; then
        cp -r "$pdfjs" pdfjs
        chmod -R u+w pdfjs
        patch -d pdfjs -p1 < Meta/CMake/vcpkg/overlay-ports/pdfjs/0001-ladybird-embed.patch
    fi
fi

echo "prepare-tree: $directory is ready for a build against system libraries"
echo "prepare-tree: configure it with"
echo "prepare-tree:   cmake -GNinja -BBuild/release -DPDFJS_DIR=$PWD/pdfjs"
