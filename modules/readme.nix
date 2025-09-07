{ config, ... }:
{
  text.readme = {
    order = [
      "intro"
      "automatic-import"
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
