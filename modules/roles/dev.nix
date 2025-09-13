{ config, ... }:
{
  # Development role: aggregate precise per-app modules via apps namespace
  flake.nixosModules.roles.dev.imports =
    (with config.flake.nixosModules.apps; [
      neovim
      vim
      cmake
      gcc
      gnumake
      pkg-config
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
      gdb
      valgrind
      strace
      ltrace
      # FHS-based dev tools
      vscodeFhs
      kiroFhs
    ])
    # Include Node dev namespace bundle (runtime + package managers)
    ++ [ config.flake.nixosModules.dev.node ];
}
