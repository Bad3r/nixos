/*
  Package: pkg-config
  Description: Tool for querying installed libraries to obtain compiler and linker flags.
  Homepage: https://www.freedesktop.org/wiki/Software/pkg-config/
  Documentation: https://people.freedesktop.org/~dbn/pkg-config-guide.html
  Repository: https://gitlab.freedesktop.org/pkg-config/pkg-config

  Summary:
    * Parses `.pc` metadata files installed by libraries to report include paths, linker flags, and version information for build systems.
    * Supports multiple search prefixes via `PKG_CONFIG_PATH`, `PKG_CONFIG_LIBDIR`, and cross-compilation settings.

  Options:
    pkg-config --cflags <package>: Print compiler flags needed to use a package.
    pkg-config --libs <package>: Print linker flags.
    pkg-config --modversion <package>: Show the installed version.
    pkg-config --list-all: List all available packages known to pkg-config.
    pkg-config --exists <package>: Return success if the package is available.

  Example Usage:
    * `pkg-config --cflags --libs gtk+-3.0` — Obtain compiler and linker flags for GTK 3.
    * `PKG_CONFIG_PATH=$PWD/build/lib/pkgconfig pkg-config --modversion mylib` — Query a locally built library.
    * `pkg-config --exists openssl && echo "OpenSSL available"` — Check for dependency presence in build scripts.
*/

{
  flake.nixosModules.apps."pkg-config" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."pkg-config" ];
    };

}
