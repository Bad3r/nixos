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
            ## Generated files

            The following files in this repository are generated and checked
            using [the _files_ flake-parts module](https://github.com/mightyiam/files):
          ''
        ] sortedList;
        joined = lib.concatLines withHeader;
      in
      joined + "\n";

    perSystem = psArgs: {
      make-shells.default.packages = [ psArgs.config.files.writer.drv ];
    };
  };
}
