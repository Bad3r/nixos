/*
  Language: Java
  Description: Object-oriented language designed for platform independence via JVM bytecode compilation.
  Homepage: https://www.java.com/
  Documentation: https://docs.oracle.com/en/java/
  Repository: https://github.com/openjdk/jdk

  Summary:
    * Provides Eclipse Temurin JDK 25 (formerly AdoptOpenJDK), the recommended open-source Java Development Kit distribution.
    * Supports enterprise application development with mature ecosystem, strong backwards compatibility, and extensive tooling for build, test, and deployment.

  Included Tools:
    temurin-bin-25: Eclipse Temurin JDK 25 binary distribution including javac compiler, java runtime, jar packager, and standard library.

  Example Usage:
    * `javac Main.java` — Compile Java source file to bytecode.
    * `java -jar application.jar` — Execute packaged Java application.
    * `java --version` — Display installed JDK version and build information.
    * `jshell` — Launch interactive Java REPL for experimentation and prototyping.
*/
_:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.languages.java.extended;
in
{
  options.languages.java.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Java language support.";
    };

    packages = {
      jdk = lib.mkPackageOption pkgs "temurin-bin-25" { };
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      "temurin-bin-25".extended = {
        enable = lib.mkOverride 1050 true;
        package = cfg.packages.jdk;
      };
    };
  };
}
