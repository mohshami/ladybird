# The Ladybird browser, packaged without vcpkg.
#
# Upstream builds its third-party dependencies with vcpkg, which does not work
# inside a Nix sandbox. This expression uses Nixpkgs' packages instead, the way
# Nixpkgs' own `ladybird` package does, with the changes this commit needs:
#
#   * LLVM libc's headers, which AK/MathFunctions.cpp and the Rust crates need.
#   * The PDF.js viewer, which is now found with the FindPDFJS.cmake module
#     instead of the vcpkg tree.
#   * The renamed CMake options (LADYBIRD_ENABLE_LTO, LADYBIRD_BASELINE_CPU_TARGET).
{
  lib,
  stdenv,
  fetchFromGitHub,

  src,
  llvm-libc-headers,

  # Build tools
  cargo,
  cmake,
  gitMinimal,
  glslang,
  ninja,
  perl,
  pkg-config,
  python3,
  rustc,
  rustPlatform,
  qt6Packages,

  # Libraries
  angle,
  brotli,
  chromium-hsts-preload-list,
  cpptrace,
  curlFull,
  dbus,
  ffmpeg,
  fast-float,
  fontconfig,
  glib,
  harfbuzz,
  icu78,
  libavif,
  libdrm,
  libedit,
  libGL,
  libjpeg_turbo,
  libpng,
  libpulseaudio,
  libpsl,
  libwebp,
  mimalloc,
  openssl,
  pdfjs,
  sdl3,
  simdjson,
  simdutf,
  skia,
  sqlite,
  vulkan-headers,
  vulkan-loader,
  vulkan-memory-allocator,
  woff2,
  wuffs,
  zmij,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ladybird";
  version = "0-unstable-2026-11-18";

  inherit src;

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version src;
    hash = "sha256-gzJxwjaSc5oFlr85t3fMjboi5U9Z5Ok8NLWvsKaUwzQ=";
  };

  nativeBuildInputs = [
    cargo
    cmake
    gitMinimal
    glslang
    ninja
    perl
    pkg-config
    python3
    rustc
    rustPlatform.cargoSetupHook
    qt6Packages.wrapQtAppsHook
  ];

  buildInputs = [
    angle # libEGL
    brotli
    chromium-hsts-preload-list
    cpptrace
    curlFull # Websocket support
    dbus
    fast-float
    (ffmpeg.overrideAttrs (prev: {
      # Ladybird's Vulkan video decoder needs the FFmpeg patches that upstream
      # keeps in its vcpkg port. They are not in Nixpkgs' FFmpeg.
      patches = (prev.patches or [ ]) ++ [
        ../Meta/CMake/vcpkg/overlay-ports/ffmpeg/0101-vulkan-decode-dpb-distinct-no-drm-modifiers.patch
        ../Meta/CMake/vcpkg/overlay-ports/ffmpeg/0102-vulkan-av1-clear-unused-ref-frame-mvs.patch
      ];
    }))
    fontconfig
    glib
    harfbuzz
    icu78
    libavif
    libdrm
    libedit
    libGL
    libjpeg_turbo
    libpng
    libpsl
    libpulseaudio.dev
    libwebp
    llvm-libc-headers
    (mimalloc.overrideAttrs (prev: {
      # Ladybird uses mi_heap_set_default(), which mimalloc 3 removed.
      version = "2.2.7";
      src = fetchFromGitHub {
        owner = "microsoft";
        repo = "mimalloc";
        tag = "v2.2.7";
        hash = "sha256-z9qMOTcGkURblZChXDGfQ58hrql52lG6EE1NQmxxuj0=";
      };
      # Ladybird's vcpkg port builds mimalloc without padding in release
      # builds, because the padding of the secure build wastes memory.
      cmakeFlags = prev.cmakeFlags ++ [ "-DMI_NO_PADDING=ON" ];
      doCheck = false;
    }))
    openssl
    pdfjs
    qt6Packages.qtbase
    qt6Packages.qtpositioning
    qt6Packages.qtwayland
    sdl3
    simdjson
    simdutf
    (skia.overrideAttrs (prev: {
      # Ladybird also uses Skia's color management API directly.
      gnFlags = prev.gnFlags ++ [
        "extra_cflags+=[\"-DSKCMS_DLL\"]"
      ];
    }))
    sqlite
    vulkan-headers
    vulkan-loader
    vulkan-memory-allocator
    woff2
    wuffs
    zmij
    zlib
  ];

  postPatch = ''
    # Upstream suffixes its reduced FFmpeg build to coexist with system FFmpeg.
    # Use Nixpkgs' FFmpeg, which already provides the additional decoders.
    substituteInPlace Meta/CMake/check_for_dependencies.cmake \
      --replace-fail libavcodec-ladybird libavcodec \
      --replace-fail libavutil-ladybird libavutil \
      --replace-fail libswresample-ladybird libswresample

    # Ladybird requires ICU 78 exactly, but without this the default ICU from
    # other dependencies gets picked up instead.
    substituteInPlace Meta/CMake/check_for_dependencies.cmake \
      --replace-fail 'find_package(ICU 78.3 EXACT' 'find_package(ICU ${icu78.version} EXACT'

    # Nixpkgs' Rust is newer than the toolchain Ladybird pins, and the newer
    # compiler emits deprecation warnings that -Dwarnings turns into errors.
    substituteInPlace Meta/CMake/rust_crate.cmake \
      --replace-fail 'set(RUSTC_TARGET_FLAGS -Dwarnings ' 'set(RUSTC_TARGET_FLAGS '

    # Install the same PDF viewer assets and integration patch as the vcpkg build.
    cp -r ${pdfjs}/share/pdf.js pdfjs
    chmod -R u+w pdfjs
    patch -d pdfjs -p1 < Meta/CMake/vcpkg/overlay-ports/pdfjs/0001-ladybird-embed.patch

    # Don't set absolute paths in RPATH.
    substituteInPlace Meta/CMake/lagom_install_options.cmake \
      --replace-fail "\''${CMAKE_INSTALL_BINDIR}" "bin" \
      --replace-fail "\''${CMAKE_INSTALL_LIBDIR}" "lib"
  '';

  preConfigure = ''
    # HSTS preload data is the only remaining downloaded data cache.
    mkdir -p build/Caches/HSTSPreload
    cp ${chromium-hsts-preload-list}/share/chromium-hsts-preload-list/transport_security_state_static.json \
      build/Caches/HSTSPreload

    cmakeFlagsArray+=(
      "-DLADYBIRD_CACHE_DIR=$PWD/build/Caches"
      # The PDF.js distribution is patched into the source tree above.
      "-DPDFJS_DIR=$PWD/pdfjs"
    )
  '';

  cmakeFlags = [
    # Disable network operations.
    "-DENABLE_NETWORK_DOWNLOADS=OFF"
    # Upstream defaults to -Ctarget-cpu=native for Rust, which cc-wrapper
    # cannot strip; target a portable baseline instead.
    "-DLADYBIRD_BASELINE_CPU_TARGET=ON"
    # Ladybird requires icu 78, but without this the default icu from other
    # dependencies gets picked up instead.
    "-DICU_ROOT=${icu78.dev}"
    # The headers of LLVM libc, which AK/MathFunctions.cpp includes.
    "-DLLVM_LIBC_INCLUDE_DIR=${llvm-libc-headers}/include"
    # The helper processes live next to the browser, in libexec.
    "-DCMAKE_INSTALL_LIBEXECDIR=libexec"
  ];

  # ld: [...]/OESVertexArrayObject.cpp.o: undefined reference to symbol 'glIsVertexArrayOES'
  # ld: [...]/libGL.so.1: error adding symbols: DSO missing from command line
  # https://github.com/LadybirdBrowser/ladybird/issues/371#issuecomment-2616415434
  env.NIX_LDFLAGS = "-lGL -lfontconfig";

  meta = {
    description = "Browser using the SerenityOS LibWeb engine with a Qt GUI";
    homepage = "https://ladybird.org";
    license = lib.licenses.bsd2;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "Ladybird";
  };
})
