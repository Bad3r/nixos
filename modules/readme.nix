{ config, ... }:
{
  text.readme = {
    order = [
      "intro"
      "automatic-import"
      "aggregators"
      "roles"

      "devshell"
      "files"
      "flake-inputs-dedupe-prefix"
      "disallow-warnings"
    ];

    parts = {
      intro =
        # markdown
        ''
          # NixOS Configuration

          A NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery.

          Based on the golden standard from [mightyiam/infra](https://github.com/mightyiam/infra).

        '';

      disallow-warnings =
        # markdown
        ''
          ## Trying to disallow warnings

          This at the top level of the `flake.nix` file:

          ```nix
          nixConfig.abort-on-warn = true;
          ```

          > [!NOTE]
          > It does not currently catch all warnings Nix can produce, but perhaps only evaluation warnings.
        '';

      flake-inputs-dedupe-prefix =
        # markdown
        ''
          ## Flake inputs for deduplication are prefixed

          Some explicit flake inputs exist solely for the purpose of deduplication.
          They are the target of at least one `<input>.inputs.<input>.follows`.
          But what if in the future all of those targeting `follows` are removed?
          Ideally, Nix would detect that and warn.
          Until that feature is available those inputs are prefixed with `dedupe_`
          and placed in an additional separate `inputs` attribute literal
          for easy identification.

        '';

      automatic-import =
        # markdown
        ''
          ## Automatic import

          Nix files (they're all flake-parts modules) are automatically imported.
          Nix files prefixed with an underscore are ignored.
          No literal path imports are used.
          This means files can be moved around and nested in directories freely.

          > [!NOTE]
          > This pattern has been the inspiration of [an auto-imports library, import-tree](https://github.com/vic/import-tree).

        '';

      aggregators =
        # markdown
        ''
          ## Module Aggregators

          This flake exposes two mergeable aggregators:

          - `flake.nixosModules`: NixOS modules (freeform, nested namespaces allowed)
          - `flake.homeManagerModules`: Home Manager modules (freeform; with `base`, `gui`, and per-app under `apps`)

          Modules register themselves under these namespaces (e.g., `flake.nixosModules.pc`, `flake.homeManagerModules.base`).
          Composition uses named references, for example:

          ```nix
          { config, ... }:
          {
            configurations.nixos.myhost.module = {
              imports = with config.flake.nixosModules; [ base pc workstation ];
            };
          }
          ```

          Use `lib.hasAttrByPath` + `lib.getAttrFromPath` when selecting optional modules to avoid ordering issues.
        '';

      roles =
        # markdown
        ''
          ### Roles and App Composition

          - Roles are assembled from per-app modules under `flake.nixosModules.apps`.
          - To avoid import-order brittleness, resolve apps with `lib.hasAttrByPath` and `lib.getAttrFromPath` rather than `with`.
          - Stable role aliases are provided for hosts:

            - `flake.nixosModules."role-dev"`
            - `flake.nixosModules."role-media"`
            - `flake.nixosModules."role-net"`

          Example host composition using aliases:

          ```nix
          { config, ... }:
          {
            configurations.nixos.system76.module = {
              imports =
                (with config.flake.nixosModules; [
                  workstation
                ])
                ++ [
                  config.flake.nixosModules."role-dev"
                ];
            };
          }
          ```

          For a complete, type-correct composition plan and guidance, see
          `docs/RFC-001.md`.
        '';

      devshell =
        # markdown
        ''
          ## Development Shell

          Enter the development shell:

          ```bash
          nix develop
          ```

          Useful commands:

          - `nix fmt` – format files
          - `pre-commit run --all-files` – run all hooks
          - `update-input-branches` – rebase vendored inputs, push inputs/\* branches, and commit updated gitlinks. The helper keeps `inputs/nixpkgs` as a blobless partial clone; set `HYDRATE_NIXPKGS=1` to hydrate temporarily or `KEEP_WORKTREE=1` to leave a checked-out tree intact.

          The `build.sh` helper refuses to run if the git worktree is dirty (tracked changes, staged changes, or untracked files) to keep builds reproducible. Override with `--allow-dirty` or `ALLOW_DIRTY=1` only when you know what you’re doing.

        '';
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path_ = "README.md";
          drv = pkgs.writeText "README.md" config.text.readme;
        }
      ];
    };
}
