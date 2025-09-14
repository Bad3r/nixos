{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path_ = ".github/workflows/check.yml";
          drv = pkgs.writeText "ci-check.yml" ''
            name: Dendritic Pattern Compliance Check
            on:
              push:
                branches: [ main, master ]
              pull_request:
                branches: [ main, master ]
            jobs:
              check:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v4
                    with:
                      submodules: true
                      fetch-depth: 0
                  - name: Install Nix
                    uses: cachix/install-nix-action@v24
                    with:
                      install_url: https://releases.nixos.org/nix/nix-2.30.2/install
                      extra_nix_config: |
                        experimental-features = nix-command flakes pipe-operators
                        abort-on-warn = true
                  - name: Flake check
                    run: nix flake check --accept-flake-config
          '';
        }
      ];
      checks = {
        role-aliases-exist = pkgs.writeText "role-aliases-exist-ok" (
          if
            (config.flake.nixosModules ? "role-dev")
            && (config.flake.nixosModules ? "role-media")
            && (config.flake.nixosModules ? "role-net")
          then
            "ok"
          else
            throw "role-* alias missing"
        );

        role-aliases-structure = pkgs.writeText "role-aliases-structure-ok" (
          let
            assertList = v: if builtins.isList v then true else throw "role alias imports not a list";
          in
          builtins.seq (
            assertList config.flake.nixosModules."role-dev".imports
            && assertList config.flake.nixosModules."role-media".imports
            && assertList config.flake.nixosModules."role-net".imports
          ) "ok"
        );

        helpers-exist = pkgs.writeText "helpers-exist-ok" (
          if
            (config.flake.lib.nixos ? getApp)
            && (config.flake.lib.nixos ? getApps)
            && (config.flake.lib.nixos ? getAppOr)
            && (config.flake.lib.nixos ? hasApp)
          then
            "ok"
          else
            throw "missing one or more helper functions"
        );
      };

      # Managed files written above (README list includes workflow path).
    };
}
