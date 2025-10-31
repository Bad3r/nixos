/*
  Package: temurin-bin-25
  Description: Eclipse Temurin binary distribution of OpenJDK 25 with HotSpot JVM.
  Homepage: https://adoptium.net/
  Documentation: https://adoptium.net/docs/faq/
  Repository: https://github.com/adoptium/temurin-build

  Summary:
    * Provides prebuilt OpenJDK binaries from the Eclipse Adoptium project, including `java`, `javac`, `jlink`, and other JDK tools.
    * Suitable for running and building Java applications that target the current Java 25 release.

  Options:
    java --version: Display JVM version and vendor details.
    javac <files>: Compile Java source files.
    jar --create --file app.jar -C out .: Package compiled classes into a JAR.
    jlink --module-path <path> --add-modules <modules> --output <dir>: Create custom runtime images.

  Example Usage:
    * `javac Main.java {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} java Main` — Compile and run a Java application.
    * `jshell` — Start the interactive Java REPL for prototyping.
    * `JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))` — Export the JDK root for build tools.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  TemurinBin25Module = {
    options.programs."temurin-bin-25".extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable Temurin JDK 25.";
      };

      package = lib.mkPackageOption pkgs "temurin-bin-25" { };
    };

    config =
      let
        cfg = config.programs."temurin-bin-25".extended;
      in
      lib.mkIf cfg.enable {
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "temurin-bin-25" ];

        environment.systemPackages = [ cfg.package ];
      };
  };
in
{
  flake.nixosModules.apps."temurin-bin-25" = TemurinBin25Module;
}
