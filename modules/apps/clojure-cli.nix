/*
  Package: clojure-cli
  Description: Official Clojure CLI tools for running code, managing deps.edn, and invoking REPLs.
  Homepage: https://clojure.org/
  Documentation: https://clojure.org/guides/deps_and_cli
  Repository: https://github.com/clojure/tools.deps

  Summary:
    * Provides `clj` and `clojure` commands for starting REPLs, running scripts, and managing dependency aliases in `deps.edn`.
    * Integrates with tools.deps to resolve classpaths reproducibly while supporting exec (`-X`), tool (`-T`), and main (`-M`) workflows.

  Options:
    -M[aliases]: Run a Clojure program using main-oriented aliases (for example `-M:test`).
    -X[aliases] fn [k v...]: Invoke a function with data arguments supplied after the alias list.
    -T[tool]: Execute a tools.deps tool such as `-Tnew` or `-T:project/-build` without starting a REPL.
    -P: Pre-fetch dependencies and cache the classpath without executing user code.
    -Sdeps '{...}': Merge inline dependency data into the current invocation.

  Example Usage:
    * `clj` — Start an interactive REPL with the current project's dependencies.
    * `clojure -M:test` — Run tests using the `:test` alias defined in `deps.edn`.
    * `clojure -X:deps tree` — Print the dependency tree to diagnose version conflicts.
*/
_:
let
  ClojureCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."clojure-cli".extended;
    in
    {
      options.programs."clojure-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Clojure CLI.";
        };

        package = lib.mkPackageOption pkgs "clojure" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."clojure-cli" = ClojureCliModule;
}
