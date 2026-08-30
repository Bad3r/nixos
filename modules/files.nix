{
  inputs,
  config,
  withSystem,
  lib,
  ...
}:
{
  imports = [ (inputs.files + "/flake-module.nix") ];

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
        files = withSystem (builtins.head config.systems) (psArgs: psArgs.config.files.file);
        filteredFiles = lib.filter (path: path != ".treefmt.toml") (builtins.attrNames files);
        fileList = map (path: "- `${path}`") filteredFiles;
        sortedList = lib.naturalSort fileList;
        withHeader = lib.concat [
          # markdown
          ''
            ## Generated Files

            The following files are defined in Nix and generated via [mightyiam/files](https://github.com/mightyiam/files) using `nix develop path:. -c write-files` (drop `path:.` in the primary checkout):
          ''
        ] sortedList;
        joined = lib.concatLines withHeader;
      in
      # The joined generated-file list already ends with its line separator.
      # Avoid adding a second one, which leaves a blank line at EOF in README.md.
      joined;

    perSystem =
      { pkgs, config, ... }:
      let
        # Get the list of managed files for reporting
        managedFiles = builtins.attrNames config.files.file;
        managedFilesList = builtins.concatStringsSep "\n" (map (f: "  - ${f}") managedFiles);

        # Wrap the original writer with verbose output
        verboseWriter = pkgs.writeShellApplication {
          name = "write-files";
          runtimeInputs = [ config.files.writer.drv ];
          text = /* bash */ ''
            echo "📝 Writing managed files..."
            echo ""

            # Condition form: writeShellApplication enables errexit, so a bare
            # invocation would abort here and leave the failure branch dead.
            if ${config.files.writer.drv}/bin/${config.files.writer.exeFilename} "$@"; then
              echo ""
              echo "✅ Successfully wrote ${toString (builtins.length managedFiles)} file(s):"
              echo "${managedFilesList}"
            else
              exit_code=$?
              echo ""
              echo "❌ write-files failed with exit code $exit_code"
              exit "$exit_code"
            fi
          '';
        };
      in
      {
        # Expose the verbose wrapper instead of the raw writer
        make-shells.default.packages = [ verboseWriter ];
      };
  };
}
