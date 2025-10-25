{ config, ... }:
{
  text.readme = {
    order = [
      "intro"
      "automatic-import"
      "aggregators"
      "system76"

      "devshell"
      "secrets"
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

          Modules register themselves under two mergeable aggregators:

          - `flake.nixosModules`: NixOS modules (freeform, nested namespaces allowed)
          - `flake.homeManagerModules`: Home Manager modules (freeform; with `base`, `gui`, and per-app under `apps`)

          Composition now centers on the single System76 host, so imports reference the exact feature modules that machine needs:

          ```nix
          { config, lib, ... }:
          {
            configurations.nixos.system76.module = {
              imports = lib.filter (module: module != null) [
                (config.flake.nixosModules.base or null)
                (config.flake.nixosModules."system76-support" or null)
                (config.flake.nixosModules."hardware-lenovo-y27q-20" or null)
              ];
            };
          }
          ```

          Continue to use `lib.hasAttrByPath` and `lib.getAttrFromPath` when selecting optional modules to avoid ordering issues.

        '';

      system76 =
        # markdown
        ''
          ### System76 Host Layout

          All packages and services now live under `modules/system76/`. Each file contributes directly to `configurations.nixos.system76.module`, so the host is assembled from explicit feature modules rather than abstract roles.

          Highlights:

          - `modules/system76/packages.nix` – core packages and unfree allow-list for the System76 laptop.
          - `modules/system76/dev-languages.nix` – imports language toolchains via `flake.nixosModules.apps.<name>` for Python, Go, Rust, and Clojure.
          - `modules/system76/home-manager-gui.nix` – wires the shared GUI Home Manager module and any extra app imports exposed by other modules.
          - `modules/system76/security-tools.nix`, `modules/system76/sudo.nix`, `modules/system76/zsh.nix`, etc. – replace the old workstation bundle with host-scoped modules.

          Because there is only one host (`configurations.nixos.system76`), you can follow the code in `modules/system76/` to understand exactly how the system is configured without navigating role indirection.

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

          The `build.sh` helper refuses to run if the git worktree is dirty (tracked changes, staged changes, or untracked files) to keep builds reproducible. Override with `--allow-dirty` or `ALLOW_DIRTY=1` only when you know what you’re doing.

        '';

      secrets =
        # markdown
        ''
          ## Adding a new secret with sops-nix

          1. **Encrypt the payload** – run `sops secrets/<name>.yaml` (or `sops -e -i …`) so the file is stored as ciphertext. The canonical `.sops.yaml` in this repo already targets everything under `secrets/`.
          2. **Declare the secret in Nix** – add an entry under `sops.secrets."<namespace>/<name>"` (system or Home Manager). Point `sopsFile` to the encrypted file, set `key` when selecting a single YAML attribute, and write the decrypted material to a runtime path using `%r`.
          3. **Consume via the module API** – reference `config.sops.secrets."<namespace>/<name>".path` (or `placeholder`) from services, wrappers, or templates. Never read secrets at evaluation time.

          Example (Context7 MCP key for Codex):

          ```nix
          sops.secrets."context7/api-key" = {
            sopsFile = ./../../secrets/context7.yaml;
            key = "context7_api_key";
            path = "%r/context7/api-key";
            mode = "0400";
          };
          ```

          The Codex module wraps the decrypted path in a small script and only enables the MCP server when the secret exists, keeping evaluation pure while allowing runtime access.

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
