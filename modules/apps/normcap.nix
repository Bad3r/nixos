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
      normcapTrayIcon = ../stylix/icons/normcap-tray.svg;
      normcapTrayDoneIcon = ../stylix/icons/normcap-tray-done.svg;

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
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          pkgs.librsvg
          pkgs.qt6.qtbase
        ];

        postInstall = (old.postInstall or "") + ''
          renderNormcapTrayIcon() {
            local size="$1"
            local source="$2"
            local output="$3"
            local glyphSize="$((size * 11 / 16))"
            local offset="$(((size - glyphSize) / 2))"

            ${pkgs.librsvg}/bin/rsvg-convert \
              --page-width "$size" \
              --page-height "$size" \
              --width "$glyphSize" \
              --height "$glyphSize" \
              --left "$offset" \
              --top "$offset" \
              --keep-aspect-ratio \
              "$source" > "$output"
          }

          resourceDirs=("$out"/lib/python*/site-packages/normcap/resources/icons)
          guiDirs=("$out"/lib/python*/site-packages/normcap/gui)
          resourceDir="''${resourceDirs[0]}"
          guiDir="''${guiDirs[0]}"

          if [ ! -d "$resourceDir" ] || [ ! -d "$guiDir" ]; then
            echo "NormCap resource directories were not found under $out" >&2
            exit 1
          fi

          renderNormcapTrayIcon 256 ${normcapTrayIcon} "$resourceDir/tray.png"
          renderNormcapTrayIcon 256 ${normcapTrayDoneIcon} "$resourceDir/tray_done.png"

          (
            cd "$resourceDir"
            ${pkgs.qt6.qtbase}/libexec/rcc -g python resources.qrc -o "$guiDir/resources.py"
          )
          sed -i '1i # ruff: noqa' "$guiDir/resources.py"
        '';

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
