/*
  Package: babashka
  Description: Native Clojure scripting runtime with instant startup and batteries included tooling.
  Homepage: https://babashka.org/
  Documentation: https://book.babashka.org/
  Repository: https://github.com/babashka/babashka

  Summary:
    * Executes Clojure scripts with near-instant startup, pods, and task automation via `bb.edn`.
    * Bundles a curated JVM-less standard library plus integrations for shelling out, HTTP, data processing, and more.

  Options:
    -e, --eval <expr>: Evaluate a Clojure expression directly from the command line.
    -f, --file <path>: Run a script file, resolving `bb.edn` dependencies automatically.
    -m, --main <ns|var>: Invoke a namespace's `-main` function or a fully qualified var.
    -x, --exec <var>: Execute a task-style function, parsing CLI args through babashka's CLI tooling.
    tasks: List tasks defined in the active `bb.edn` configuration.

  Example Usage:
    * `bb -e '(+ 1 2 3)'` -- Evaluate an inline expression and print the result.
    * `bb -x greet --name Alice` -- Call a function exported in `bb.edn` with parsed CLI options.
    * `bb tasks` -- Inspect available tasks defined in the project `bb.edn` file.
*/
_:
let
  BabashkaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.babashka.extended;
    in
    {
      options.programs.babashka.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable babashka.";
        };

        package = lib.mkPackageOption pkgs "babashka" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.babashka = BabashkaModule;
}
