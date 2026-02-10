_: {
  perSystem =
    { config, ... }:
    {
      pre-commit = {
        # Custom hooks rely on git metadata; skip sandboxed flake checks.
        check.enable = false;

        settings = {
          excludes = [
            "^inputs/"
            "^nixos-manual/"
          ];

          default_stages = [
            "pre-commit"
            "manual"
          ];

          hooks = {
            check-json.enable = true;

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

            vulnix = {
              enable = true;
              name = "vulnix";
              description = "Scan flake dependencies for known vulnerabilities.";
              entry = "${config.packages.hook-vulnix}/bin/hook-vulnix";
              pass_filenames = false;
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
              description = "Ensure modules/system76/apps-enable.nix matches modules/apps/";
              entry = "${config.packages.hook-apps-catalog-sync}/bin/hook-apps-catalog-sync";
              pass_filenames = false;
              always_run = true;
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
