# The headers of LLVM's libc.
#
# Ladybird computes its math functions with LLVM libc's header-only
# implementations (AK/MathFunctions.cpp), and the Rust crates use them too
# (AK/Rust/build.rs). Upstream gets them from vcpkg, which installs the headers
# of the `libc` directory of an llvm-project checkout.
#
# Ladybird pins a commit of llvm-project's main branch instead of a release,
# because the double-precision sinh, cosh and tanh that AK/MathFunctions.h asks
# for are not in a release yet. The pin is in vcpkg.json:
#
#   { "name": "llvm-libc", "version": "e54169423e7ee5d8b41c2f1b6f7a59000c901ee0#0" }
#
# Only the headers are installed, and only the ones the math functions need.
{
  lib,
  stdenvNoCC,
  cacert,
  git,
}:

stdenvNoCC.mkDerivation {
  pname = "llvm-libc-headers";
  version = "unstable-e54169423e7ee5d8b41c2f1b6f7a59000c901ee0";

  dontUnpack = true;
  nativeBuildInputs = [
    cacert
    git
  ];

  # The llvm-project checkout is huge, and only the libc directory of it is
  # needed, so fetch the commit with a partial clone and a sparse checkout
  # instead of downloading a tarball of the whole project.
  installPhase = ''
    runHook preInstall

    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_TERMINAL_PROMPT=0

    git init -q .
    git remote add origin https://github.com/llvm/llvm-project.git
    git config core.sparseCheckout true
    mkdir -p .git/info
    echo libc/ > .git/info/sparse-checkout
    git fetch -q --depth 1 --filter=blob:none origin \
      e54169423e7ee5d8b41c2f1b6f7a59000c901ee0
    git checkout -q FETCH_HEAD

    # The same directories the vcpkg port installs.
    mkdir -p $out/include/llvm-libc
    for directory in hdr include shared src/__support src/string/memory_utils; do
      if [ -d "libc/$directory" ]; then
        mkdir -p "$out/include/llvm-libc/$(dirname "$directory")"
        cp -r "libc/$directory" "$out/include/llvm-libc/$directory"
      fi
    done
    find $out -type f ! -name '*.h' -delete

    runHook postInstall
  '';

  # The headers of a given commit never change, so the output is fixed.
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-C0ewr8lcUf1WjIGoPy2RdCZkbI/HoszeMlmP9zRiqHg=";

  meta = {
    description = "Headers of LLVM libc, for Ladybird's math functions";
    homepage = "https://github.com/llvm/llvm-project";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
}
