_: {
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
        jnv # Interactive JSON filter
        tokei
        hyperfine
        git-filter-repo
        exiftool
        niv # Nix dependency management
        tealdeer # Fast tldr client

        # Network Tools
        curl
        wget
        httpie
        mitmproxy

        # Terminal UI Tools
        circumflex # Hacker News terminal client (clx)

        # Debugging Tools
        gdb
        valgrind
        strace
        ltrace
      ];
    };
}
