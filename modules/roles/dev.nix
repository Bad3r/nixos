{ config, ... }:
{
  # Development role: aggregate precise per-app modules via apps namespace
  flake.modules.nixos.roles.dev.imports =
    (with config.flake.modules.nixos.apps; [
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
    ])
    # Include Node dev namespace bundle (runtime + package managers)
    ++ [ config.flake.modules.nixos.dev.node ];
}
