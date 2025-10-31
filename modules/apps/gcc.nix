/*
  Package: gcc
  Description: GNU Compiler Collection including C, C++, and other frontends.
  Homepage: https://gcc.gnu.org/
  Documentation: https://gcc.gnu.org/onlinedocs/
  Repository: https://gcc.gnu.org/git/gcc.git

  Summary:
    * Provides the GNU toolchain for compiling C, C++, Objective-C, Fortran, Ada, Go, and D depending on enabled frontends.
    * Includes `gcc`, `g++`, and related utilities such as `gcov`, `gprof`, and `cpp` for development, profiling, and preprocessing.

  Options:
    -O[0-3,s,g]: Control optimization level (from none to aggressive size/performance tuning).
    -g, -ggdb: Emit debug symbols for use with debuggers.
    -Wall, -Wextra: Enable broad warning categories to catch defects early.
    -I <dir>, -L <dir>: Add include or library search paths.
    --std=<dialect>: Compile using a specific language standard (e.g. `--std=c17`, `--std=gnu++20`).

  Example Usage:
    * `gcc main.c -Wall -Wextra -O2 -o app` — Compile a C program with warnings and optimisation.
    * `g++ src/*.cc --std=c++20 -I include/ -L lib/ -lmylib -o program` — Build a C++20 project linking against local libraries.
    * `gcc -S foo.c` — Generate assembly output for inspection or low-level debugging.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  GccModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gcc.extended;
    in
    {
      options.programs.gcc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable gcc.";
        };

        package = lib.mkPackageOption pkgs "gcc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gcc = GccModule;
}
