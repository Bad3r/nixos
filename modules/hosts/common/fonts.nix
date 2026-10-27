{ config, lib, ... }:
let
  symbolFallback = [
    "Symbols Nerd Font"
    "Symbols Nerd Font Mono"
    "Font Awesome 6 Free"
    "Font Awesome 6 Brands"
  ];
  monoSymbolFallback = [
    "Symbols Nerd Font Mono"
    "Symbols Nerd Font"
    "Font Awesome 6 Free"
    "Font Awesome 6 Brands"
  ];

  body =
    { config, pkgs, ... }:
    let
      privateFonts = configFonts pkgs;
    in
    {
      options.host.fontconfig.extraRules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra fontconfig XML fragments appended to the shared local.conf.";
      };
      config = {
        fonts = {
          enableDefaultPackages = true;
          packages =
            with pkgs;
            [
              noto-fonts
              noto-fonts-cjk-sans
              noto-fonts-color-emoji
              liberation_ttf
              # Genuine Microsoft fonts (Arial, Times New Roman, Webdings, ...) so
              # Office documents render their embedded faces instead of substitutes.
              corefonts
              font-awesome_6
              material-icons
              nerd-fonts.symbols-only
            ]
            ++ lib.optional (privateFonts ? monolisa) privateFonts.monolisa;

          fontconfig = {
            defaultFonts = {
              serif = [
                "MonoLisaText"
                "Noto Serif"
              ]
              ++ symbolFallback;
              sansSerif = [
                "MonoLisaText"
                "Noto Sans"
              ]
              ++ symbolFallback;
              monospace = [
                "MonoLisaCode"
                "Liberation Mono"
              ]
              ++ monoSymbolFallback;
              emoji = [
                "Noto Color Emoji"
                "Symbols Nerd Font"
                "Symbols Nerd Font Mono"
              ];
            };
            localConf = ''
              <?xml version="1.0"?>
              <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
              <fontconfig>
                ${config.host.fontconfig.extraRules}
              </fontconfig>
            '';
          };
        };
      };
    };
  configFonts = config.flake.lib.fonts.packages;
in
{
  nixpkgs.allowedUnfreePackages = [
    "corefonts"
    "monolisa"
  ];
  flake.nixosModules.hosts-common.imports = [ body ];
}
