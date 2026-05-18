{ config, ... }:
{
  text.readme = {
    order = [
      "logo"
      "intro"
      "automatic-import"
      "build"
      "hm-package-pattern"
      "secrets"
      "flake-input-deduplication"
      "files"
    ];

    parts = {
      logo =
        # markdown
        ''
          <p align="center">
            <a href="https://nixos.org">
              <picture>
                <source media="(prefers-color-scheme: light)" srcset="https://brand.nixos.org/logos/nixos-logo-default-gradient-black-regular-horizontal-minimal.svg">
                <source media="(prefers-color-scheme: dark)" srcset="https://brand.nixos.org/logos/nixos-logo-default-gradient-white-regular-horizontal-minimal.svg">
                <img src="https://brand.nixos.org/logos/nixos-logo-default-gradient-black-regular-horizontal-minimal.svg" width="500px" alt="NixOS logo">
              </picture>
            </a>
          </p>


        '';

      intro =
        # markdown
        ''
          # NixOS Configuration

          NixOS Infrastructure as Code using the [Dendritic Pattern](https://github.com/mightyiam/dendritic), an organic configuration growth pattern with automatic module discovery. Powered by [flake-parts](https://flake.parts/).

        '';

      automatic-import =
        # markdown
        ''
          ## Automatic Import

          All Nix files are flake-parts modules and are automatically imported via [import-tree](https://github.com/vic/import-tree). Files prefixed with `_` are omitted. No literal path imports are used, so files can be moved and nested freely.

        '';

      build =
        # markdown
        ''
          ## Build and Deployment

          This project uses a custom build script, [`build.sh`](build.sh), for validation and deployment:

          ```bash
          ./build.sh              # validate and deploy
          ./build.sh --boot       # install for next boot only
          ./build.sh --update     # refresh metadata + update flake inputs
          ./build.sh --offline    # Offline build
          ```

          The script runs a validation pipeline (format, pre-commit hooks, flake check) before deployment.
          It refuses to run on a dirty worktree by default; use `--allow-dirty` to override.
          `--update` intentionally allows dirty worktrees and does not auto-commit `flake.lock`.

          **Development commands:**

          | Command                                                         | Description     |
          | --------------------------------------------------------------- | --------------- |
          | `nix develop`                                                   | Enter dev shell |
          | `nix fmt`                                                       | Format files    |
          | `nix develop -c pre-commit run --all-files --hook-stage manual` | Run all hooks   |

        '';

      hm-package-pattern =
        # markdown
        ''
          ## Home Manager Package Pattern

          This repo uses a dual-module approach: NixOS modules install packages, HM modules configure them. To avoid duplicate installation, HM modules set `package = null` when supported.

          See the [App Modules Style Guide](docs/guides/apps-module-style-guide.md#6-create-home-manager-module) for details.

        '';

      secrets =
        # markdown
        ''
          ## Secrets

          Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix). Encrypted payloads live in `secrets/`, a private git submodule, and are declared via `sops.secrets`.

          See the [sops documentation](docs/sops/README.md) for usage instructions.

        '';

      flake-input-deduplication =
        # markdown
        ''
          ## Flake Input Deduplication

          These root inputs pin shared dependencies used through `.follows` declarations. `systems` keeps the canonical `nix-systems` input name even though dependency inputs also follow it.

          | Input                 | Followed By                                                  |
          | --------------------- | ------------------------------------------------------------ |
          | `dedupe_flake-compat` | `make-shell.inputs.flake-compat`                             |
          | `dedupe_flake-utils`  | `claude-desktop-linux-flake.inputs.flake-utils`              |
          | `dedupe_nur`          | `stylix.inputs.nur`                                          |
          | `systems`             | `dedupe_flake-utils.inputs.systems`, `stylix.inputs.systems` |

        '';

    };
  };

  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path = "README.md";
          drv = pkgs.writeText "README.md" config.text.readme;
        }
      ];
    };
}
