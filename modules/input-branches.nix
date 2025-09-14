{
  inputs,
  lib,
  rootPath,
  ...
}:
{
  imports = [ inputs.input-branches.flakeModules.default ];

  input-branches.inputs = {
    nixpkgs = {
      upstream = {
        url = "github:NixOS/nixpkgs";
        ref = "nixpkgs-unstable";
      };
      shallow = true;
    };
    home-manager.upstream = {
      url = "github:nix-community/home-manager";
      ref = "master";
    };
    stylix.upstream = {
      url = "github:nix-community/stylix";
      ref = "master";
    };
  };

  # Import mitigation module and (optionally) force nixpkgs source to the local input path
  flake.nixosModules.base = {
    imports = [ inputs.input-branches.modules.nixos.default ];
    nixpkgs.flake.source = lib.mkForce (rootPath + "/inputs/nixpkgs");
  };

  perSystem = psArgs: {
    # Expose input-branches commands in the dev shell
    make-shells.default.packages = psArgs.config.input-branches.commands.all;

    # Exclude input branches from formatting for speed
    treefmt.settings.global.excludes = [ "${psArgs.config.input-branches.baseDir}/*" ];

    # Note: no pre-push hook is installed for inputs/* branches.
  };
}
