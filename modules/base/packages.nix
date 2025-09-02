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

        # Text processing
        less
        diffutils
        patch

        # File management
        file
        findutils
        gawk
        gnugrep
        gnused
        which
        tree
        rsync

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
        traceroute
        mtr
        nmap
        tcpdump
        iftop
        nethogs

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
        bc

        # Terminal multiplexers
        tmux
        screen

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
