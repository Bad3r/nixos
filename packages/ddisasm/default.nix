{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
  cmake,
  ninja,
  boost187,
  capstone,
  souffle,
}:

let
  pin = (lib.importJSON ./hashes.json).ddisasm;
  dependencies = callPackage ./dependencies.nix { };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ddisasm";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "GrammaTech";
    repo = "ddisasm";
    inherit (pin) rev hash;
  };

  nativeBuildInputs = [
    cmake
    ninja
    capstone
    souffle
  ];
  buildInputs = [
    boost187
    capstone
    dependencies.gtirb
    dependencies.gtirb-pprinter
    dependencies.libehp
    dependencies.lief
  ];

  cmakeFlags = [
    (lib.cmakeBool "DDISASM_ENABLE_TESTS" false)
    (lib.cmakeBool "DDISASM_USE_SYSTEM_BOOST" true)
    (lib.cmakeBool "DDISASM_GENERATE_MANY" true)
    (lib.cmakeFeature "DDISASM_BUILD_REVISION" pin.rev)
    (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
  ];

  passthru = {
    updateScript = ./update.py;
    inherit dependencies;
    tests.roundtrip = callPackage ./test.nix { ddisasm = finalAttrs.finalPackage; };
  };

  meta = {
    description = "Datalog disassembler producing reassemblable assembly and GTIRB";
    homepage = "https://github.com/GrammaTech/ddisasm";
    changelog = "https://github.com/GrammaTech/ddisasm/blob/${pin.rev}/CHANGELOG.md";
    license = lib.licenses.agpl3Only;
    mainProgram = "ddisasm";
    platforms = lib.platforms.linux;
  };
})
