
{ lib, config, ... }:
let
  username = config.flake.meta.owner.username;
  nodejs = config.flake.meta.packages.nodejs;
  python = config.flake.meta.packages.python;
  postgresql = config.flake.meta.packages.postgresql;
in
{
  flake.modules.nixos.workstation = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # Version Control
      git
      gh
      lazygit
      delta
      
      # Editors
      neovim
      helix
      vscode-fhs
      
      # Language Tools (versions from metadata)
      pkgs.${nodejs}
      pkgs.${python}
      rustc
      cargo
      go
      clojure
      
      # Build Tools
      cmake
      gnumake
      gcc
      pkg-config
      
      # Development Utilities
      jq
      yq
      ripgrep
      fd
      bat
      eza
      tokei
      hyperfine
      
      # Database Tools
      pkgs.${postgresql}
      redis
      sqlite
      
      # Container Tools
      docker-compose
      dive
      lazydocker
      
      # Network Tools
      curl
      wget
      httpie
      mitmproxy
      
      # Debugging Tools
      gdb
      valgrind
      strace
      ltrace
    ];
    
    # Enable Docker
    virtualisation.docker = {
      enable = true;
      enableOnBoot = lib.mkDefault true;  # Enable on boot by default
    };
    
    # Enable NVIDIA container toolkit (replaces deprecated enableNvidia)
    hardware.nvidia-container-toolkit.enable = true;
    
    # Docker group is already added in system76-complete.nix for this workstation
  };
}