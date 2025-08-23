{ lib, ... }:
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
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

        # Clipboard utilities
        xclip
        xsel

        # Network tools
        curl
        wget
        iputils
        iproute2
        dnsutils
        nettools

        # Text editors
        neovim

        # System monitoring
        htop
        iotop
        lsof
        sysstat

        # Version control
        git

        # Shell utilities
        bash-completion
        zsh-completions
        starship
        zoxide
        atuin

        # System information
        pciutils
        usbutils
        lshw
        dmidecode
        exiftool

        # Development basics
        gnumake
        gcc
        binutils
        pkg-config
        biome

        # Nix utilities
        nix-output-monitor
        nvd
        nix-tree
        nil # Nix LSP
      ];
    };
}
