/*
  Package: temurin-bin-24
  Description: Eclipse Temurin binary distribution of OpenJDK 24 (early access/EA) with HotSpot JVM.
  Homepage: https://adoptium.net/
  Documentation: https://adoptium.net/docs/faq/
  Repository: https://github.com/adoptium/temurin-build

  Summary:
    * Provides prebuilt OpenJDK binaries from the Eclipse Adoptium project, including `java`, `javac`, `jlink`, and other JDK tools.
    * Suitable for running and building Java applications that target the upcoming Java 24 release.

  Options:
    java --version: Display JVM version and vendor details.
    javac <files>: Compile Java source files.
    jar --create --file app.jar -C out .: Package compiled classes into a JAR.
    jlink --module-path <path> --add-modules <modules> --output <dir>: Create custom runtime images.

  Example Usage:
    * `javac Main.java && java Main` — Compile and run a Java application.
    * `jshell` — Start the interactive Java REPL for prototyping.
    * `JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))` — Export the JDK root for build tools.
*/

{
  nixpkgs.allowedUnfreePackages = [ "temurin-bin-24" ];

  flake.nixosModules.apps."temurin-bin-24" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };

}
