/*
  Package: cmake
  Description: Cross-platform build system generator for C/C++ and other compiled languages.
  Homepage: https://cmake.org/
  Documentation: https://cmake.org/cmake/help/latest/manual/cmake.1.html
  Repository: https://gitlab.kitware.com/cmake/cmake

  Summary:
    * Generates native build configurations (Ninja, Makefiles, Visual Studio, Xcode) from declarative CMakeLists.txt files.
    * Supports presets, toolchain files, and package discovery to enable reproducible multi-platform builds.

  Options:
    -S <src> -B <build>: Configure a project from a source directory into a dedicated build tree.
    -DVAR=VALUE: Define or override cache entries such as feature flags or dependency paths.
    --build <dir> [--target <name>]: Invoke the configured generator to build specific targets.
    --install <dir>: Install compiled artifacts according to CMake install rules.
    -P <script.cmake>: Run CMake in scripting mode to execute automation tasks.

  Example Usage:
    * `cmake -S . -B build -DCMAKE_BUILD_TYPE=Release` — Configure a release build in a separate directory.
    * `cmake --build build --target tests` — Compile and run the `tests` target using the selected generator.
    * `cmake --install build --prefix /opt/myapp` — Install artifacts into a staging prefix after a successful build.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.cmake.extended;
  CmakeModule = {
    options.programs.cmake.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable cmake.";
      };

      package = lib.mkPackageOption pkgs "cmake" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.cmake = CmakeModule;
}
