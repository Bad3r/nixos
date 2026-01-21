{
  inputs,
  config,
  withSystem,
  lib,
  ...
}:
{
  imports = [ inputs.files.flakeModules.default ];

  options.text = lib.mkOption {
    default = { };
    type = lib.types.lazyAttrsOf (
      lib.types.oneOf [
        (lib.types.separatedString "")
        (lib.types.submodule {
          options = {
            parts = lib.mkOption {
              type = lib.types.lazyAttrsOf lib.types.str;
            };
            order = lib.mkOption {
              type = lib.types.listOf lib.types.str;
            };
          };
        })
      ]
    );
    apply = lib.mapAttrs (
      _: text:
      if lib.isAttrs text then
        lib.pipe text.order [
          (map (lib.flip lib.getAttr text.parts))
          lib.concatStrings
        ]
      else
        text
    );
  };

  config = {
    text.readme.parts.files =
      let
        files = withSystem (builtins.head config.systems) (psArgs: psArgs.config.files.files);
        filteredFiles = lib.filter (file: file.path_ != ".treefmt.toml") files;
        fileList = map (file: "- `${file.path_}`") filteredFiles;
        sortedList = lib.naturalSort fileList;
        withHeader = lib.concat [
          # markdown
          ''
            ## Generated Files

            The following files are defined in Nix and generated via [mightyiam/files](https://github.com/mightyiam/files) using `nix develop -c write-files`:
          ''
        ] sortedList;
        joined = lib.concatLines withHeader;
      in
      joined + "\n";

    perSystem =
      { pkgs, config, ... }:
      let
        # Get the list of managed files for reporting
        managedFiles = map (f: f.path_) config.files.files;
        managedFilesList = builtins.concatStringsSep "\n" (map (f: "  - ${f}") managedFiles);

        # Wrap the original writer with verbose output
        verboseWriter = pkgs.writeShellApplication {
          name = "write-files";
          runtimeInputs = [ config.files.writer.drv ];
          text = /* bash */ ''
            echo "📝 Writing managed files..."
            echo ""

            # Run the actual writer
            ${config.files.writer.drv}/bin/write-files "$@"
            exit_code=$?

            if [ $exit_code -eq 0 ]; then
              echo ""
              echo "✅ Successfully wrote ${toString (builtins.length managedFiles)} file(s):"
              echo "${managedFilesList}"
            else
              echo ""
              echo "❌ write-files failed with exit code $exit_code"
            fi

            exit $exit_code
          '';
        };
      in
      {
        # Expose the verbose wrapper instead of the raw writer
        make-shells.default.packages = [ verboseWriter ];
      };
  };
}
