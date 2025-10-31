/*
  Package: leiningen
  Description: Automation tool for Clojure projects providing project scaffolding, dependency management, and task runner.
  Homepage: https://leiningen.org/
  Documentation: https://github.com/technomancy/leiningen#readme
  Repository: https://github.com/technomancy/leiningen

  Summary:
    * Manages Clojure projects via `project.clj`, handling dependencies, builds, REPL integration, and deployment tasks.
    * Offers extensive plugin ecosystem, profiles, and scripted tasks for testing, packaging, and releasing applications.

  Options:
    lein new <template> <name>: Scaffold projects using built-in or custom templates.
    lein repl: Start an interactive REPL with project classpath loaded.
    lein test: Run the project's test suite.
    lein uberjar: Build an executable uberjar bundling all dependencies.
    lein run [args]: Run the project's `-main` function with arguments.

  Example Usage:
    * `lein new app example` — Create a new application skeleton.
    * `lein repl` — Launch a REPL with the project's dependencies available.
    * `lein uberjar` — Package the project into a standalone jar for deployment.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.leiningen.extended;
  LeiningenModule = {
    options.programs.leiningen.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable leiningen.";
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
