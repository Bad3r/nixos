{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 developer toolchain.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

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
