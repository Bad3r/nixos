# Priority: All packages use mkDefault for easy override

{ lib, ... }:
{
  flake.modules.nixos.base = { pkgs, ... }: {
    environment.systemPackages = with pkgs; lib.mkDefault [
      # Core utilities
      coreutils
      util-linux
      procps
      psmisc
      
      # File management
      file
      findutils
      gawk
      gnugrep
      gnused
      which
      tree
      
      # Network tools
      curl
      wget
      iputils
      iproute2
      dnsutils
      nettools
      
      # Text editors
      vim
      nano
      
      # System monitoring
      htop
      iotop
      lsof
      sysstat
      
      # Archive tools
      gzip
      bzip2
      xz
      zip
      unzip
      tar
      
      # Version control
      git
      
      # Shell utilities
      bash-completion
      zsh-completions
      
      # System information
      pciutils
      usbutils
      lshw
      dmidecode
      
      # Development basics
      gnumake
      gcc
      binutils
      pkg-config
      
      # Nix utilities
      nix-output-monitor
      nvd
      nix-tree
      nil  # Nix LSP
    ];
  };
}