/*
  Package: gnumake
  Description: GNU Make build automation tool.
  Homepage: https://www.gnu.org/software/make/
  Documentation: https://www.gnu.org/software/make/manual/make.html
  Repository: https://git.savannah.gnu.org/git/make.git

  Summary:
    * Automates builds using Makefiles that describe dependencies and rules, orchestrating incremental builds efficiently.
    * Supports parallel execution, pattern rules, automatic variables, and integration with a variety of toolchains.

  Options:
    -f <file>: Use an alternate Makefile.
    -j [N]: Run up to N jobs in parallel (default: unlimited concurrency).
    -C <dir>: Change to directory before reading the Makefile.
    -k: Keep going when some targets cannot be made.
    --trace: Print commands as they are executed with dependency context (GNU extension).

  Example Usage:
    * `make` -- Build the default target described in `Makefile` or `makefile`.
    * `make -j$(nproc)` -- Compile targets in parallel according to CPU count.
    * `make clean` -- Invoke the `clean` target to remove build artifacts.
*/
_:
let
  GnumakeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gnumake.extended;
    in
    {
      options.programs.gnumake.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gnumake.";
        };

        package = lib.mkPackageOption pkgs "gnumake" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gnumake = GnumakeModule;
}
