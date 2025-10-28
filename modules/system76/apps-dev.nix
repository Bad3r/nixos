{ config, lib, ... }:
let
  appsDir = ../apps;
  helpers = config._module.args.nixosAppHelpers or { };
  fallbackGetApp =
    name:
    let
      filePath = appsDir + "/${name}.nix";
    in
    if builtins.pathExists filePath then
      let
        exported = import filePath;
        module = lib.attrByPath [
          "flake"
          "nixosModules"
          "apps"
          name
        ] null exported;
      in
      if module != null then
        module
      else
        throw ("NixOS app '" + name + "' missing expected attrpath in " + toString filePath)
    else
      throw ("NixOS app module file not found: " + toString filePath);
  getApp = helpers.getApp or fallbackGetApp;
  getApps = helpers.getApps or (names: map getApp names);

  devAppNames = [
    # editors and viewers
    "neovim"
    "vim"
    "glow"
    # build tools
    "cmake"
    "gcc"
    "gnumake"
    "pkg-config"
    "formatting"
    # JSON/YAML and inspection
    "jq"
    "yq"
    "jnv"
    "tokei"
    "hyperfine"
    "git-filter-repo"
    "forgit"
    "exiftool"
    "httpie"
    "yaak"
    "mitmproxy"
    # debugging and tracing
    "gdb"
    "valgrind"
    "strace"
    "ltrace"
    "ent"
    # Node toolchains and managers
    "nodejs_24"
    "nodejs_22"
    "yarn"
    "nrm"
    # FHS-based dev environments
    "vscodeFhs"
    "kiroFhs"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps devAppNames;
}
