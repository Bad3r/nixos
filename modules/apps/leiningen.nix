/*
  Package: leiningen
  Description: Automation tool for Clojure projects providing project scaffolding, dependency management, and task runner.
  Homepage: https://leiningen.org/
  Documentation: https://github.com/technomancy/leiningen#readme
  Repository: https://codeberg.org/leiningen/leiningen

  Summary:
    * Manages Clojure projects via `project.clj`, handling dependencies, builds, REPL integration, and deployment tasks.
    * Offers a plugin ecosystem, profiles, and scripted tasks for testing, packaging, and releasing applications.

  Options:
    lein new <template> <name>: Scaffold projects using built-in or custom templates.
    lein repl: Start an interactive REPL with project classpath loaded.
    lein test: Run the project's test suite.
    lein uberjar: Build an executable uberjar bundling all dependencies.
    lein run [args]: Run the project's `-main` function with arguments.
*/
_:
let
  LeiningenModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.leiningen.extended;
    in
    {
      options.programs.leiningen.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable leiningen.";
        };

        package = lib.mkPackageOption pkgs "leiningen" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.leiningen = LeiningenModule;
}
