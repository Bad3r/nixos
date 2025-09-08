{ lib, ... }:
{
  # Manage GitHub Actions workflow via files writer
  perSystem =
    { pkgs, lib, ... }:
    let
      githubTokenRef = "\${{ secrets.GITHUB_TOKEN }}";
      toY = lib.generators.toYAML { };
      workflow = toY {
        name = "Dendritic Pattern Compliance Check";
        on = {
          push.branches = [
            "main"
            "master"
          ];
          pull_request.branches = [
            "main"
            "master"
          ];
        };
        jobs = {
          "check-compliance" = {
            "runs-on" = "ubuntu-latest";
            steps = [
              {
                uses = "actions/checkout@v4";
                "with" = {
                  submodules = true;
                  "fetch-depth" = 0;
                };
              }
              {
                name = "Install Nix";
                uses = "cachix/install-nix-action@v24";
                "with" = {
                  install_url = "https://releases.nixos.org/nix/nix-2.30.2/install";
                  github_access_token = githubTokenRef;
                  extra_nix_config = lib.concatStrings [
                    "experimental-features = nix-command flakes pipe-operators\n"
                    "abort-on-warn = true\n"
                    "access-tokens = github.com="
                    githubTokenRef
                    "\n"
                  ];
                };
              }
              {
                name = "Prefer HTTPS for GitHub";
                run = lib.concatStrings [
                  ''git config --global url."https://github.com/".insteadOf git@github.com:''
                  "\n"
                  ''git config --global url."https://github.com/".insteadOf ssh://git@github.com/''
                ];
              }
              {
                name = "Check flake";
                run = "nix flake check --extra-experimental-features pipe-operators";
              }
              {
                name = "Check namespace compliance";
                run = "./test-dendritic-compliance.sh";
              }
              {
                name = "Build configurations";
                run = lib.concatStrings [
                  "nix build .#nixosConfigurations.system76.config.system.build.toplevel \\\n"
                  "  --dry-run --extra-experimental-features pipe-operators"
                ];
              }
              {
                name = "Generate dependency graph";
                run = "./generate-dependency-graph.sh";
              }
              {
                name = "Upload artifacts";
                uses = "actions/upload-artifact@v4";
                "if" = "always()";
                "with" = {
                  name = "dependency-graph";
                  path = lib.concatStrings [
                    "module-dependencies.dot\n"
                    "module-dependencies.png\n"
                    "module-dependencies.svg\n"
                  ];
                  "retention-days" = 30;
                };
              }
            ];
          };

          "format-check" = {
            "runs-on" = "ubuntu-latest";
            steps = [
              {
                uses = "actions/checkout@v4";
                "with" = {
                  submodules = true;
                  "fetch-depth" = 0;
                };
              }
              {
                name = "Install Nix";
                uses = "cachix/install-nix-action@v24";
                "with" = {
                  install_url = "https://releases.nixos.org/nix/nix-2.30.2/install";
                  github_access_token = githubTokenRef;
                  extra_nix_config = lib.concatStrings [
                    "experimental-features = nix-command flakes pipe-operators\n"
                    "access-tokens = github.com="
                    githubTokenRef
                    "\n"
                  ];
                };
              }
              {
                name = "Check formatting";
                run = "nix fmt -- --check --extra-experimental-features pipe-operators";
              }
            ];
          };

          "module-validation" = {
            "runs-on" = "ubuntu-latest";
            steps = [
              {
                uses = "actions/checkout@v4";
                "with" = {
                  submodules = true;
                  "fetch-depth" = 0;
                };
              }
              {
                name = "Install Nix";
                uses = "cachix/install-nix-action@v24";
                "with" = {
                  install_url = "https://releases.nixos.org/nix/nix-2.30.2/install";
                  github_access_token = githubTokenRef;
                  extra_nix_config = lib.concatStrings [
                    "experimental-features = nix-command flakes pipe-operators\n"
                    "access-tokens = github.com="
                    githubTokenRef
                    "\n"
                  ];
                };
              }
              {
                name = "Validate namespaces";
                run = lib.concatStrings [
                  "# Check that no modules create wrong namespaces\n"
                  ''! grep -r "flake.modules.nixos.desktop" modules/ --include="*.nix"\n''
                  ''! grep -r "flake.modules.nixos.audio" modules/ --include="*.nix"\n''
                  ''! grep -r "flake.modules.nixos.boot" modules/ --include="*.nix"\n''
                  ''! grep -r "flake.modules.nixos.storage" modules/ --include="*.nix"''
                ];
              }
              {
                name = "Check import-tree usage";
                run = "grep -q \"import-tree.*modules\" flake.nix || exit 1";
              }
              {
                name = "Check no literal imports";
                run = lib.concatStrings [
                  "! grep -r \"im"
                  "ports.*\\./\" modules/ --include=\"*.nix\" || exit 1"
                ];
              }
            ];
          };
        };
      };
    in
    {
      files.files = [
        {
          path_ = ".github/workflows/check.yml";
          drv = pkgs.writeText "ci-check.yml" workflow;
        }
      ];
    };
}
