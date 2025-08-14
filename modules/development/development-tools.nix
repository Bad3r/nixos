{ lib, config, ... }:
{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Editors (kept at system level for emergency access)
        neovim
        vim

        # Build Tools
        cmake
        gnumake
        gcc
        pkg-config

        # Development Utilities
        jq
        yq
        tokei
        hyperfine

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
    };
}
