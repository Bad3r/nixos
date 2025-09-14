{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
  importsList =
    # Core dev apps (explicit)
    getApps [
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
      # FHS-based dev tools
      "vscodeFhs"
      "kiroFhs"
    ]
    # Node toolchain bundle (single source of truth):
    # includes: nodejs_22, nodejs_24, yarn, nrm
    ++ [ config.flake.nixosModules.dev.node ];
in
{
  flake.nixosModules.roles.dev.imports = importsList;
  flake.nixosModules."role-dev".imports = importsList;
}
