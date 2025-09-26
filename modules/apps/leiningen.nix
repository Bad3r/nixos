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
  flake.nixosModules.apps.leiningen =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.leiningen ];
    };

}
