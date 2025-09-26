{ config, ... }:
let
  helpers = config.flake.lib.nixos or { };
  assertList = v: if builtins.isList v then true else throw "role module imports not a list";
  hasRoles = builtins.hasAttr "roles" config.flake.nixosModules;
  roleModuleExists =
    name: if hasRoles then builtins.hasAttr name config.flake.nixosModules.roles else false;
  workflowYml =
    let
      githubTokenRef = "\${{ secrets.GITHUB_TOKEN }}";
      importsPattern = "im" + "ports.*\\./";
    in
    ''
      name: Dendritic Pattern Compliance Check
      on:
        workflow_dispatch:
      jobs:
        check-compliance:
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
                github_access_token: ${githubTokenRef}
                extra_nix_config: |
                  experimental-features = nix-command flakes pipe-operators
                  abort-on-warn = true
                  access-tokens = github.com=${githubTokenRef}
            - name: Prefer HTTPS for GitHub
              run: |
                git config --global url."https://github.com/".insteadOf git@github.com:
                git config --global url."https://github.com/".insteadOf ssh://git@github.com/
            - name: Check flake
              run: nix flake check --extra-experimental-features pipe-operators
            - name: Check namespace compliance
              run: ./test-dendritic-compliance.sh
            - name: Build configurations
              run: |
                nix build .#nixosConfigurations.system76.config.system.build.toplevel \
                  --dry-run --extra-experimental-features pipe-operators
            - name: Generate dependency graph
              run: ./generate-dependency-graph.sh
            - name: Upload artifacts
              if: always()
              uses: actions/upload-artifact@v4
              with:
                name: dependency-graph
                path: |
                  module-dependencies.dot
                  module-dependencies.png
                  module-dependencies.svg
                retention-days: 30

        format-check:
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
                github_access_token: ${githubTokenRef}
                extra_nix_config: |
                  experimental-features = nix-command flakes pipe-operators
                  access-tokens = github.com=${githubTokenRef}
            - name: Check formatting
              run: nix fmt -- --check --extra-experimental-features pipe-operators

        module-validation:
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
                github_access_token: ${githubTokenRef}
                extra_nix_config: |
                  experimental-features = nix-command flakes pipe-operators
                  access-tokens = github.com=${githubTokenRef}
            - name: Validate namespaces
              run: |
                # Check that no modules create wrong namespaces
                ! grep -r "flake.nixosModules.desktop" modules/ --include="*.nix"
                ! grep -r "flake.nixosModules.audio" modules/ --include="*.nix"
                ! grep -r "flake.nixosModules.boot" modules/ --include="*.nix"
                ! grep -r "flake.nixosModules.storage" modules/ --include="*.nix"
            - name: Check import-tree usage
              run: grep -q "import-tree.*modules" flake.nix || exit 1
            - name: Check no literal imports
              run: '! grep -r "${importsPattern}" modules/ --include="*.nix" || exit 1'
    '';
in
{
  flake.checks = {
    role-modules-exist = builtins.toFile "role-modules-exist-ok" (
      if roleModuleExists "dev" && roleModuleExists "media" && roleModuleExists "net" then
        "ok"
      else
        throw "role module missing"
    );

    role-modules-structure = builtins.toFile "role-modules-structure-ok" (
      builtins.seq (assertList config.flake.nixosModules.roles.dev.imports) (
        builtins.seq (assertList config.flake.nixosModules.roles.media.imports) (
          builtins.seq (assertList config.flake.nixosModules.roles.net.imports) "ok"
        )
      )
    );

    helpers-exist = builtins.toFile "helpers-exist-ok" (
      if (helpers ? getApp) && (helpers ? getApps) && (helpers ? getAppOr) && (helpers ? hasApp) then
        "ok"
      else
        throw "missing helper(s) under config.flake.lib.nixos"
    );
  };

  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path_ = ".github/workflows/check.yml";
          drv = pkgs.writeText "ci-check.yml" workflowYml;
        }
      ];
    };
}
