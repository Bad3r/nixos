{ config, ... }:
{
  text.readme = {
    order = [
      "logo"
      "intro"
      "automatic-import"
      "build"
      "hm-package-pattern"
      "app-wiring"
      "storage-boundaries"
      "cache-boundaries"
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

          Shared device policy that serves multiple optional applications belongs in `modules/hosts/common/`, so its permissions do not disappear when one app module is disabled. Optional app modules own their package and capability-wrapper behavior, including compiled argv filters with audited, grammar-aware allowlists that fail closed on unsupported and non-device forms, validate parser-dependent argument boundaries, and bound the resulting no-sudo operation boundary.

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

          | Command                                                               | Description     |
          | --------------------------------------------------------------------- | --------------- |
          | `nix develop path:.`                                                  | Enter dev shell |
          | `nix run path:.#treefmt -- .`                                          | Format files    |
          | `nix develop path:. -c pre-commit run --all-files --hook-stage manual` | Run all hooks   |

          These carry the explicit `path:.` installable because the branch workflow in [`AGENTS.md`](AGENTS.md) puts the work in a linked worktree, where Lix cannot fetch a clean checkout as a `git+file` flake: `.git` is a file there, not a directory. Dropping `path:.` gives the primary-checkout form, where `nix fmt` also works. Two cases `path:.` cannot fix: `nix fmt`, because Lix hardcodes the `.` installable in `lix/nix/fmt.cc`; and any command that writes `flake.lock` back, such as `nix flake metadata --refresh` and `nix flake update`, which need an absolute ref like `"path:$PWD"`.

        '';

      hm-package-pattern =
        # markdown
        ''
          ## Home Manager Package Pattern

          This repo uses a dual-module approach: NixOS modules install packages, HM modules configure them. To avoid duplicate installation, HM modules set `package = null` when supported.

          See the [App Modules Style Guide](docs/guides/apps-module-style-guide.md#6-create-home-manager-module) for details.

        '';

      app-wiring =
        # markdown
        ''
          ## App Wiring

          Nested host app overrides register full option paths and route them through `programs` first, then `services` for services-only paths. A path absent from both baseline namespaces fails the host evaluation, so it cannot be dropped by a switch that never runs the FR-5 check.

          See the [App Modules Style Guide](docs/guides/apps-module-style-guide.md) for the routing and validation contract.

        '';

      storage-boundaries =
        # markdown
        ''
          ## Storage Boundaries

          Storage-dependent services must be enabled only on hosts that provide their required mount. The system76 host has no dedicated `/data`, so it disables both common local mirror writers and the R2 runtime; the relocated `/data` volume belongs to `songbird`.

          See the [local mirror reference](docs/reference/local-mirrors.md), [system76 configuration](docs/system76/system76-configuration.md), and [R2 runtime policy](docs/r2-cloud/system76-runtime.md) for the operational contracts.

        '';

      cache-boundaries =
        # markdown
        ''
          ## Cache Boundaries

          Cache-root membership is derived from evaluated host configuration. Every NVIDIA-enabled host explicitly sets `cacheRoots.nvidiaKernelModules`; missing, malformed, or unknown policy values fail evaluation. songbird sets it to `false` to keep its source-built CachyOS module out while retaining `nvidia-x11` and `nvidia-settings` coverage.

          See [binary cache coverage](docs/reference/binary-cache-coverage.md) for the inventory and operator policy.

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

          These root inputs pin shared dependencies used through `.follows` declarations. `systems` keeps the canonical `nix-systems` input name even though dependency inputs also follow it. The table lists dedicated dedupe roots and canonical non-nixpkgs roots; ordinary root followers such as `nixpkgs` are declared beside each dependent input. Remove any `dedupe_*` input once no `.follows` declaration references it.

          | Input                 | Followed By                                                  |
          | --------------------- | ------------------------------------------------------------ |
          | `dedupe_flake-compat` | `make-shell.inputs.flake-compat`, `nix-cachyos-kernel.inputs.flake-compat` |
          | `dedupe_flake-utils`  | `claude-desktop-linux-flake.inputs.flake-utils`              |
          | `dedupe_nur`          | `stylix.inputs.nur`                                          |
          | `systems`             | `dedupe_flake-utils.inputs.systems`, `stylix.inputs.systems` |

        '';

    };
  };

  perSystem = _: {
    files.file."README.md".text = config.text.readme;
  };
}
