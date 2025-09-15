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

  perSystem =
    psArgs:
    let
      hasIB = psArgs.config ? input-branches;
      hasBaseDir = hasIB && (psArgs.config.input-branches ? baseDir);
      hasCommands = hasIB && (psArgs.config.input-branches ? commands);
    in
    lib.mkMerge [
      (lib.mkIf hasCommands {
        # Expose input-branches commands in the dev shell (when available)
        make-shells.default.packages = psArgs.config.input-branches.commands.all;
      })

      (lib.mkIf hasBaseDir {
        # Exclude vendored inputs from formatting for speed (when baseDir is known)
        treefmt.settings.global.excludes = [ "${psArgs.config.input-branches.baseDir}/*" ];
      })

      # Note: no pre-push hook is installed for inputs/* branches.
    ];
}
