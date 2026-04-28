/*
  Package: normcap
  Description: Screenshot-to-text utility that recognizes text and copies it to the clipboard.
  Homepage: https://github.com/dynobo/normcap
  Documentation: https://github.com/dynobo/normcap#readme

  Summary:
    * Launches directly into selection mode for quick OCR snips.
    * Supports X11 and Wayland backends with clipboard integration.
    * Provides optional system tray indicator and history view.
    * OCR languages are provided by the configured `tesseract` package
      (tesseract4 ships all 132 traineddata files, including Arabic).
*/

_:
let
  NormcapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.normcap.extended;

      # normcap's Python code derives tessdata_path as $TESSDATA_PREFIX/tessdata, so
      # TESSDATA_PREFIX must point to the *parent* of the tessdata/ directory.  The
      # nixpkgs tesseract wrapper exports TESSDATA_PREFIX=…/share/tessdata (the dir
      # itself) but only inside the tesseract subprocess; the parent normcap process
      # never sees it.  Setting it here gives normcap a valid tessdata_path so the
      # Language Manager and OCR both find the bundled data.
      # TODO: upstream a `--set-default TESSDATA_PREFIX` to nixpkgs' normcap wrapper.
      wrapperArgs = [
        "--set"
        "TESSDATA_PREFIX"
        "${cfg.tesseract}/share"
      ]
      ++ lib.optionals (cfg.languages != [ ]) [
        "--add-flags"
        "-l ${lib.concatStringsSep " " cfg.languages}"
      ];

      finalPackage = cfg.package.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/normcap ${lib.escapeShellArgs wrapperArgs}
        '';
      });
    in
    {
      options.programs.normcap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable normcap screenshot OCR utility.";
        };

        package = lib.mkPackageOption pkgs "normcap" { };

        tesseract = lib.mkPackageOption pkgs "tesseract4" {
          extraDescription = ''
            Tesseract package whose `share/tessdata` directory is exposed to
            normcap via `TESSDATA_PREFIX`.
          '';
        };

        languages = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "ara"
            "eng"
          ];
          description = ''
            Language codes prepended as `-l <codes...>` to every normcap launch.
            normcap persists CLI values into its QSettings store, so a non-empty
            list overwrites the GUI's saved language selection on every startup.
            Leave empty (the default) to let normcap manage languages through its
            GUI. Codes must exist in the configured `tesseract` package's
            tessdata directory; otherwise OCR fails at runtime.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ finalPackage ];
      };
    };
in
{
  flake.nixosModules.apps.normcap = NormcapModule;
}
