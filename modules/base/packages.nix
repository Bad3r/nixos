_: {
  flake.modules.nixos.base =
    { pkgs, lib, ... }:
    {
      # Minimal core defaults. Additional tooling comes from roles or per-app modules.
      environment.systemPackages = lib.mkBefore (
        with pkgs;
        [
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

          # Clipboard utilities
          xclip
          xsel

          # Version control (baseline)
          git

          # Shell utilities
          bash-completion
          zsh-completions
          starship
          zoxide
          atuin
          bc

          # System monitoring/info
          htop
          lsof
          sysstat
          pciutils
          usbutils
          lshw
          dmidecode

          # Nix utilities
          nix-output-monitor
          nvd
          nix-tree
          nil # Nix LSP
        ]
      );
    };
}
