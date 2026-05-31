_: {
  perSystem =
    { config, pkgs, ... }:
    let
      flakeCheckerCondition = builtins.concatStringsSep " " [
        "supportedRefs.contains(gitRef)"
        "&& has(numDaysOld)"
        "&& numDaysOld < 30"
        "&& owner == 'Bad3r'"
      ];
    in
    {
      pre-commit = {
        # Custom hooks rely on git metadata; skip sandboxed flake checks.
        check.enable = false;

        settings = {
          excludes = [
            "^inputs/"
            "^docs/nixos-manual/"
          ];

          default_stages = [
            "pre-commit"
            "manual"
          ];

          hooks = {
            check-json.enable = true;

            shellcheck.enable = true;

            actionlint.enable = true;

            ruff.enable = true;

            pyright = {
              enable = true;
              files = "\\.py$";
              pass_filenames = false;
              stages = [
                "pre-push"
                "manual"
              ];
            };

            yamllint = {
              enable = true;
              settings.preset = "relaxed";
            };

            treefmt = {
              enable = true;
              settings.fail-on-change = true;
              settings.no-cache = true;
              require_serial = true;
            };

            deadnix.enable = true;

            # Built-in statix hook doesn't pass filenames; keep staged-only behavior.
            statix = {
              enable = true;
              pass_filenames = true;
              entry = "${config.packages.hook-statix}/bin/hook-statix";
            };

            nix-parse = {
              enable = true;
              name = "nix-parse";
              description = "Parse staged Nix files with nix-instantiate --parse.";
              entry = "${config.packages.hook-nix-parse}/bin/hook-nix-parse";
              pass_filenames = true;
              files = "\\.nix$";
            };

            luacheck = {
              enable = true;
              entry = "${config.packages.hook-luacheck}/bin/hook-luacheck";
            };

            typos = {
              enable = true;
              settings.configPath = ".typos.toml";
            };

            pre-commit-hook-ensure-sops = {
              enable = true;
              files = "^secrets/.*\\.(yaml|yml|json|env|ini|age|enc)$";
            };

            gitleaks = {
              enable = true;
              name = "gitleaks";
              description = "Detect hardcoded secrets in repository history.";
              entry = "${config.packages.hook-gitleaks}/bin/hook-gitleaks";
              pass_filenames = false;
              always_run = true;
              stages = [
                "pre-push"
                "manual"
              ];
            };

            flake-checker = {
              enable = true;
              name = "flake-checker";
              description = "Check flake.lock Nixpkgs inputs for supported upstream freshness.";
              entry = builtins.concatStringsSep " " [
                "${pkgs.flake-checker}/bin/flake-checker"
                "--no-telemetry"
                "--fail-mode"
                "--condition \"${flakeCheckerCondition}\""
              ];
              pass_filenames = false;
              files = "";
              always_run = true;
              stages = [
                "pre-push"
                "manual"
              ];
            };

            managed-files-drift = {
              enable = true;
              name = "managed-files-drift";
              description = "Ensure managed files are synced with Nix definitions.";
              entry = "${config.packages.hook-managed-files-drift}/bin/hook-managed-files-drift";
              pass_filenames = false;
              always_run = true;
              stages = [
                "pre-push"
                "manual"
              ];
            };

            apps-catalog-sync = {
              enable = true;
              name = "apps-catalog-sync";
              description = "Ensure apps-enable.nix files match modules/apps/ for each modified host.";
              entry = "${config.packages.hook-apps-catalog-sync}/bin/hook-apps-catalog-sync";
              pass_filenames = false;
              always_run = true;
              stages = [
                "pre-push"
                "manual"
              ];
            };

            build-sh-completion-sync = {
              enable = true;
              name = "build-sh-completion-sync";
              description = "Ensure modules/apps/build-sh-completion.nix lists the same flags as build.sh.";
              entry = "${config.packages.hook-build-sh-completion-sync}/bin/hook-build-sh-completion-sync";
              pass_filenames = false;
              files = "^(build\\.sh|modules/apps/build-sh-completion\\.nix)$";
              stages = [
                "pre-push"
                "manual"
              ];
            };

            mcp-docs-sync = {
              enable = true;
              name = "mcp-docs-sync";
              description = "Ensure MCP reference docs match the generated agents.mcp output.";
              entry = "${config.packages.hook-mcp-docs-sync}/bin/hook-mcp-docs-sync";
              pass_filenames = false;
              files = "^(modules/agents/mcp\\.nix|modules/agents/mcp/servers\\.nix)$";
              stages = [
                "pre-push"
                "manual"
              ];
            };
          };
        };
      };
    };
}
