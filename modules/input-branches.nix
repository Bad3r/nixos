{
  config,
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
        url = "https://github.com/NixOS/nixpkgs.git";
        ref = "nixpkgs-unstable";
      };
      shallow = true;
    };
    home-manager.upstream = {
      url = "https://github.com/nix-community/home-manager.git";
      ref = "master";
    };
    stylix.upstream = {
      url = "https://github.com/nix-community/stylix.git";
      ref = "master";
    };
  };

  # Import mitigation module and (optionally) force nixpkgs source to the local input path
  flake.modules.nixos.base = {
    imports = [ inputs.input-branches.modules.nixos.default ];
    nixpkgs.flake.source = lib.mkForce (rootPath + "/inputs/nixpkgs");
  };

  perSystem =
    psArgs@{ pkgs, ... }:
    {
      # Expose input-branches commands in the dev shell
      make-shells.default.packages = psArgs.config.input-branches.commands.all;

      # Exclude input branches from formatting for speed
      treefmt.settings.global.excludes = [ "${config.input-branches.baseDir}/*" ];

      # Pre-push hook to ensure submodule commits are pushed
      pre-commit.settings.hooks.check-submodules-pushed = {
        enable = true;
        stages = [ "pre-push" ];
        always_run = true;
        verbose = true;
        entry = lib.getExe (
          pkgs.writeShellApplication {
            name = "check-submodules-pushed";
            runtimeInputs = [
              pkgs.git
              pkgs.gnugrep
            ];
            text =
              let
                inputValues = lib.attrValues config.input-branches.inputs;
                chunks = map (v: ''
                  (
                    unset GIT_DIR
                    cd ${v.path_}
                    current_commit=$(git rev-parse --quiet HEAD)
                    [ -z "$current_commit" ] && {
                      echo "Error: could not find HEAD of submodule ${v.path_}"
                      exit 1
                    }
                    status=$(git status --porcelain)
                    echo "$status" | grep -q . && {
                      echo "Error: submodule ${v.path_} not clean"
                      exit 1
                    }
                    git fetch upstream
                    git ls-remote upstream --heads | grep -q "$current_commit" || {
                      echo "Error: submodule ${v.path_} commit $current_commit is not pushed"
                      exit 1
                    }
                  )
                '') inputValues;
                withHeader = lib.concat [
                  ''
                    set -o xtrace
                  ''
                ] chunks;
              in
              lib.concatLines withHeader;
          }
        );
      };
    };
}
