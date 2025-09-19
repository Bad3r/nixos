{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackHasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;
  fallbackGetApp = name: lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;
  fallbackGetApps = names: map fallbackGetApp (lib.filter fallbackHasApp names);
  getApps = rawHelpers.getApps or fallbackGetApps;
  devApps = [
    # editors
    "neovim"
    "vim"
    # build tools
    "cmake"
    "gcc"
    "gnumake"
    "pkg-config"
    # JSON/YAML/tools
    "jq"
    "yq"
    "jnv"
    "tokei"
    "hyperfine"
    "git-filter-repo"
    "exiftool"
    "niv"
    "tealdeer"
    "httpie"
    "mitmproxy"
    # debugging
    "gdb"
    "valgrind"
    "strace"
    "ltrace"
    # Node toolchains and managers
    "nodejs_22"
    "nodejs_24"
    "yarn"
    "nrm"
    # FHS-based dev tools
    "vscodeFhs"
    "kiroFhs"
  ];
  roleImports = getApps devApps;
in
{
  # Development role: aggregate per-app modules through shared helpers.
  flake.nixosModules.roles.dev.imports = roleImports;

  # Stable alias for host imports to avoid duplicating lists across modules.
  flake.nixosModules."role-dev".imports = roleImports;
}
