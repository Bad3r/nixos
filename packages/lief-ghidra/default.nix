{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
  ghidra-extensions,
  lief,
  cmake,
  ninja,
  unzip,
  jdk25,
}:

let
  pin = (lib.importJSON ./hashes.json)."jni-bind";
  jniBind = fetchFromGitHub {
    owner = "google";
    repo = "jni-bind";
    inherit (pin) rev hash;
  };

  nativeBridge = stdenv.mkDerivation {
    pname = "lief-ghidra-jni";
    inherit (lief) version src;

    nativeBuildInputs = [
      cmake
      ninja
      unzip
      jdk25
    ];
    buildInputs = [ lief ];
    env.JAVA_HOME = jdk25.home;
    env.NIX_CFLAGS_COMPILE = "-DSPDLOG_NO_EXCEPTIONS -DSPDLOG_DISABLE_DEFAULT_LOGGER -DSPDLOG_FUNCTION=";

    postUnpack = ''
      sourceRoot="$sourceRoot/plugins/ghidra"
    '';

    postPatch = ''
      # Match the bundled spdlog/fmt ABI used by the LIEF library.
      unzip -q ../../third-party/spdlog-*.zip -d bundled-spdlog
      spdlog_include=$(find "$PWD/bundled-spdlog" -type d -path '*/include/spdlog' -print -quit)
      substituteInPlace CMakeLists.txt \
        --replace-fail 'find_package(spdlog REQUIRED)' \
          "add_library(spdlog::spdlog INTERFACE IMPORTED)
      set_target_properties(spdlog::spdlog PROPERTIES INTERFACE_INCLUDE_DIRECTORIES \"$(dirname "$spdlog_include")\")" \
        --replace-fail 'find_package(ghidra-jni REQUIRED)' "" \
        --replace-fail 'find_package(JNI    REQUIRED)' 'find_package(JNI REQUIRED COMPONENTS JVM)' \
        --replace-fail '  ghidra::ghidra-jni' ""
      substituteInPlace jni/ghidra_logger_sink.hpp \
        --replace-fail '#include <ghidra/util/Msg.hpp>' '#include "jni/ghidra-msg.hpp"'
      cp ${./ghidra-msg.hpp} jni/ghidra-msg.hpp
      # jni-bind 1.5 defines these thread locals inline.
      substituteInPlace jni/lief/Utils.cpp \
        --replace-fail 'thread_local int jni::ThreadGuard::thread_guard_count_ = 0;' "" \
        --replace-fail $'thread_local jni::ThreadLocalGuardDestructor\n    jni::ThreadGuard::thread_local_guard_destructor{};' ""
    '';

    cmakeFlags = [
      (lib.cmakeFeature "JNI_BIND_HINT" "${jniBind}")
    ];
    enableParallelBuilding = true;
    preBuild = ''
      NIX_BUILD_CORES=4
    '';
  };
in
ghidra-extensions.buildGhidraExtension (finalAttrs: {
  pname = "lief-ghidra";
  inherit (lief) version src;

  postUnpack = ''
    sourceRoot="$sourceRoot/plugins/ghidra"
  '';

  postPatch = ''
    # Ghidra identifies this extension by its module name, independently of pname.
    echo 'rootProject.name = "LIEF"' > settings.gradle
    substituteInPlace build.gradle \
      --replace-fail 'throw new GradleException("GHIDRA_SETTINGS_DIR is not defined!")' \
        'ghidraSettingsDir = "build/unused-install-directory"'
  '';

  preBuild = ''
    echo 'rootProject.name = "LIEF"' > settings.gradle
  '';

  postInstall = ''
    extension="$out/lib/ghidra/Ghidra/Extensions/LIEF"
    ln -s ${nativeBridge}/data/* "$extension/data/"
    ln -s ${lib.getLib lief}/lib/libLIEF.so "$extension/data/libLIEF.so"
  '';

  passthru = {
    updateScript = ./update.py;
    inherit nativeBridge;
    tests.headless = callPackage ./test.nix { lief-ghidra = finalAttrs.finalPackage; };
  };

  meta = {
    description = "LIEF executable-format analyzers and native bindings for Ghidra";
    homepage = "https://lief.re/doc/latest/plugins/ghidra/index.html";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
})
