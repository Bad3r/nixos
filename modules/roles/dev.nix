{ config, lib, ... }:
{
  # Development role: aggregate per-app modules via the apps namespace.
  # Use has/get lookup to avoid import-time ordering issues.
  flake.nixosModules."role-dev".imports =
    let
      names = [
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
        # FHS-based dev tools
        "vscodeFhs"
        "kiroFhs"
      ];
      hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;
      getApp = name: lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;
      apps = map getApp (lib.filter hasApp names);
    in
    apps
    # Include Node dev namespace bundle (runtime + package managers)
    ++ [ config.flake.nixosModules.dev.node ];
}
