{ config, ... }:
{
  # Development role: aggregate per-app modules via the apps namespace.
  # Expose under a flat key to avoid ordering issues when importing.
  flake.nixosModules."role-dev".imports =
    (with config.flake.nixosModules.apps; [
      # editors
      neovim
      vim
      # build tools
      cmake
      gcc
      gnumake
      pkg-config
      # JSON/YAML/tools
      jq
      yq
      jnv
      tokei
      hyperfine
      git-filter-repo
      exiftool
      niv
      tealdeer
      httpie
      mitmproxy
      # debugging
      gdb
      valgrind
      strace
      ltrace
      # Node toolchains and managers
      nodejs_22
      nodejs_24
      yarn
      # FHS-based dev tools
      vscodeFhs
      kiroFhs
    ])
    # Include Node dev namespace bundle (runtime + package managers)
    ++ [ config.flake.nixosModules.dev.node ];
}
