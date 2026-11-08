{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  cmake,
  ninja,
  boost187,
  protobuf_21,
  capstone,
}:

let
  pins = lib.importJSON ./hashes.json;
  gtirb = stdenv.mkDerivation {
    pname = "gtirb";
    inherit (pins.gtirb) version;
    src = fetchFromGitHub {
      owner = "GrammaTech";
      repo = "gtirb";
      inherit (pins.gtirb) rev hash;
    };
    nativeBuildInputs = [
      cmake
      ninja
    ];
    propagatedBuildInputs = [
      boost187
      protobuf_21
    ];
    cmakeFlags = [
      (lib.cmakeBool "GTIRB_ENABLE_TESTS" false)
      (lib.cmakeBool "GTIRB_PY_API" false)
      (lib.cmakeBool "GTIRB_CL_API" false)
      (lib.cmakeBool "GTIRB_JAVA_API" false)
      (lib.cmakeBool "GTIRB_DOCUMENTATION" false)
      (lib.cmakeBool "GTIRB_RUN_CLANG_TIDY" false)
      (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
    ];
    meta = {
      description = "Intermediate representation for binary analysis and rewriting";
      homepage = "https://github.com/GrammaTech/gtirb";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };
  gtirb-pprinter = stdenv.mkDerivation {
    pname = "gtirb-pprinter";
    inherit (pins.gtirb-pprinter) version;
    src = fetchFromGitHub {
      owner = "GrammaTech";
      repo = "gtirb-pprinter";
      inherit (pins.gtirb-pprinter) rev hash;
    };
    nativeBuildInputs = [
      cmake
      ninja
      capstone
    ];
    buildInputs = [ capstone ];
    propagatedBuildInputs = [
      gtirb
      boost187
    ];
    cmakeFlags = [
      (lib.cmakeBool "GTIRB_PPRINTER_ENABLE_TESTS" false)
      (lib.cmakeFeature "GTIRB_PPRINTER_BUILD_REVISION" pins.gtirb-pprinter.rev)
      (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
    ];
    meta = {
      description = "Pretty printer for reassemblable GTIRB binaries";
      homepage = "https://github.com/GrammaTech/gtirb-pprinter";
      license = lib.licenses.mit;
      mainProgram = "gtirb-pprinter";
      platforms = lib.platforms.linux;
    };
  };
  libehp = stdenv.mkDerivation {
    pname = "libehp";
    inherit (pins.libehp) version;
    src = fetchFromGitHub {
      owner = "GrammaTech";
      repo = "libehp";
      inherit (pins.libehp) rev hash;
    };
    nativeBuildInputs = [
      cmake
      ninja
    ];
    cmakeFlags = [ (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5") ];
    meta = {
      description = "Exception handling information parser";
      homepage = "https://github.com/GrammaTech/libehp";
      license = lib.licenses.asl20;
      platforms = lib.platforms.linux;
    };
  };
  # DDisasm uses the 0.16 API and requires LIEF's static CMake component.
  lief = stdenv.mkDerivation {
    pname = "lief";
    inherit (pins.lief) version;
    src = fetchFromGitHub {
      owner = "lief-project";
      repo = "LIEF";
      tag = pins.lief.version;
      inherit (pins.lief) hash;
    };
    patches = [
      # The same upstream iterator fix used by DDisasm's Dockerfile.
      (fetchpatch {
        url = "https://github.com/lief-project/LIEF/commit/6877ce7aba037074954bc63102c9d45b73d63b0b.patch";
        hash = "sha256-U84RMx2JqNONw/sN0xi2+FB9uOJxr26cBSTcosMH5E8=";
      })
    ];
    nativeBuildInputs = [
      cmake
      ninja
    ];
    cmakeFlags = [
      (lib.cmakeBool "BUILD_SHARED_LIBS" false)
      (lib.cmakeBool "LIEF_PYTHON_API" false)
      (lib.cmakeBool "LIEF_EXAMPLES" false)
      (lib.cmakeBool "LIEF_TESTS" false)
      (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
    ];
    meta = {
      description = "Library to instrument executable formats";
      homepage = "https://lief.re";
      license = lib.licenses.asl20;
      platforms = lib.platforms.linux;
    };
  };
in
{
  inherit
    gtirb
    gtirb-pprinter
    libehp
    lief
    ;
}
