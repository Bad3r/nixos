{
  nixConfig = {
    abort-on-warn = true;
    extra-experimental-features = [ "pipe-operators" ];
    allow-import-from-derivation = false;
  };

  inputs = {
    self.submodules = true;
    cpu-microcodes = {
      flake = false;
      url = "github:platomav/CPUMicrocodes";
    };

    files.url = "github:mightyiam/files";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        flake-compat.follows = "dedupe_flake-compat";
        nixpkgs.follows = "nixpkgs";
      };
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    make-shell = {
      url = "github:nicknovitski/make-shell";
      inputs.flake-compat.follows = "dedupe_flake-compat";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-logseq-git-flake = {
      url = "path:/home/vx/git/nix-logseq-git-flake";
    };

    # nix-on-droid = {
    #   url = "github:nix-community/nix-on-droid";
    #   inputs = {
    #     home-manager.follows = "home-manager";
    #     nixpkgs-docs.follows = "nixpkgs";
    #     nixpkgs-for-bootstrap.follows = "nixpkgs";
    #     nixpkgs.follows = "nixpkgs";
    #   };
    # };

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };

    secrets = {
      url = "path:./secrets";
      flake = false;
    };

    refjump-nvim = {
      flake = false;
      url = "github:mawkler/refjump.nvim";
    };

    sink-rotate = {
      #  Command that rotates the default PipeWire audio sink
      url = "github:mightyiam/sink-rotate";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "dedupe_systems";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    "burpsuite-pro-flake" = {
      url = "gitlab:_VX3r/burpsuite-pro-flake";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    smart-scrolloff-nvim = {
      flake = false;
      url = "github:tonymajestro/smart-scrolloff.nvim";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nur.follows = "dedupe_nur";
        systems.follows = "dedupe_systems";
        tinted-schemes.follows = "tinted-schemes";
      };
    };

    # Official Cloudflare language SDKs as sources (non-flake repos)
    cloudflare-go = {
      flake = false;
      url = "github:cloudflare/cloudflare-go";
    };
    cloudflare-python = {
      flake = false;
      url = "github:cloudflare/cloudflare-python";
    };
    cloudflare-rs = {
      flake = false;
      url = "github:cloudflare/cloudflare-rs";
    };
    node-cloudflare = {
      flake = false;
      url = "github:cloudflare/node-cloudflare";
    };
    workers-rs = {
      flake = false;
      url = "github:cloudflare/workers-rs";
    };

    tinted-schemes = {
      flake = false;
      url = "github:tinted-theming/schemes";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ucodenix = {
      url = "github:e-tho/ucodenix";
      inputs.cpu-microcodes.follows = "cpu-microcodes";
    };

    vim-autoread = {
      flake = false;
      url = "github:djoshea/vim-autoread/24061f84652d768bfb85d222c88580b3af138dab";
    };

    zsh-auto-notify = {
      flake = false;
      url = "github:MichaelAquilina/zsh-auto-notify";
    };

    # _additional_ `inputs` only for deduplication
    dedupe_flake-compat.url = "github:edolstra/flake-compat";

    dedupe_flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "dedupe_systems";
    };

    dedupe_nur = {
      url = "github:nix-community/NUR";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };

    dedupe_systems.url = "github:nix-systems/default";
  };

  outputs =
    inputs:
    let
      ownerProfile = import ./lib/meta-owner-profile.nix;
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        (inputs.import-tree ./modules)
      ];

      systems = [
        "x86_64-linux"
      ];

      _module.args = {
        rootPath = ./.;
        inherit inputs;
        pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
        metaOwner = ownerProfile;
      };
    };
}
