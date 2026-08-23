# Shared font stack plus the MonoLisa secret-font install pipeline. The
# encrypted archive ships MonoLisa v3 as two variable families under
# monolisa/{code,text}: MonoLisaCode (monospace) and MonoLisaText
# (proportional). The install path activates only when the encrypted archive
# exists and the host registry sets sopsRuntimeReady. Hosts append fontconfig
# rules through the host.fontconfig.extraRules option declared here.
{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  fontArchive = secretsRoot + "/fonts/monolisa.tar.zst";
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  secretExists = builtins.pathExists fontArchive;
  secretName = "fonts/monolisa.archive";
  secretRuntimePath = "/run/secrets/fonts/monolisa.archive";
  fontInstallDir = "/var/lib/fonts/monolisa";
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  # Symbol and icon fallbacks appended after the primary family; the
  # monospace list prefers the Mono variant so glyphs keep cell width.
  # Every generic class keeps a real text face ahead of these: the MonoLisa
  # families only exist once monolisa-fonts.service has installed the archive,
  # and with an icon-only face next in line `fc-match sans-serif:lang=en`
  # resolves to Symbols Nerd Font, which carries no Latin coverage.
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
    {
      config,
      hostName,
      pkgs,
      ...
    }:
    let
      installSecretsDeps = sopsInstallSecretsDeps config;
      sopsRuntimeReady = (hostsRegistry.${hostName} or { }).sopsRuntimeReady or false;
      installReady = secretExists && sopsRuntimeReady;
    in
    {
      options.host.fontconfig.extraRules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra fontconfig XML fragments appended to the shared local.conf.";
      };

      config = lib.mkMerge [
        {
          fonts = {
            enableDefaultPackages = true;
            packages = with pkgs; [
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
            ];

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
                  ${lib.optionalString installReady "<dir>${fontInstallDir}</dir>"}
                  ${config.host.fontconfig.extraRules}
                </fontconfig>
              '';
            };
          };
        }
        (lib.optionalAttrs installReady {
          sops.secrets.${secretName} = {
            sopsFile = fontArchive;
            format = "binary";
            path = secretRuntimePath;
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "monolisa-fonts.service" ];
          };

          systemd.tmpfiles.rules = [
            "d /var/lib/fonts 0755 root root -"
            "d ${fontInstallDir} 0755 root root -"
          ];

          systemd.services.monolisa-fonts = {
            description = "Install MonoLisa font families from encrypted archive";
            wantedBy = [ "multi-user.target" ];
            after = installSecretsDeps;
            requires = installSecretsDeps;
            path = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnutar
              pkgs.zstd
              pkgs.fontconfig
            ];
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              Group = "root";
              Restart = "on-failure";
            };
            script = ''
              set -euo pipefail

              if [ ! -s "${secretRuntimePath}" ]; then
                echo "MonoLisa font secret is missing or empty" >&2
                exit 1
              fi

              tmpdir="$(mktemp -d)"
              trap 'rm -rf "$tmpdir"' EXIT

              tar -C "$tmpdir" --strip-components=1 -I zstd -xf "${secretRuntimePath}"

              # Refuse to wipe the installed families unless the archive
              # carries a payload for each one. A repack missing a single
              # family would otherwise pass, wipe both, and restore one.
              for family in code text; do
                if [ -z "$(find "$tmpdir/$family" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit 2>/dev/null)" ]; then
                  echo "MonoLisa archive extracted with no font payload under $family/" >&2
                  exit 1
                fi
              done

              install -d -m 0755 "${fontInstallDir}"
              find "${fontInstallDir}" -mindepth 1 -exec rm -rf {} +

              cp -R "$tmpdir"/. "${fontInstallDir}/"

              find "${fontInstallDir}" -type d -exec chmod 0755 {} +
              find "${fontInstallDir}" -type f -exec chmod 0644 {} +

              fc-cache -f "${fontInstallDir}"
            '';
          };
        })
        (lib.optionalAttrs (secretExists && (!sopsRuntimeReady)) {
          warnings = [
            "MonoLisa secret font install is disabled on ${hostName} until flake.lib.nixos.hosts.${hostName}.sopsRuntimeReady is set."
          ];
        })
      ];
    };
in
{
  # corefonts ships under an unfree-redistributable EULA; gate it through the
  # shared allowlist so allowUnfreePredicate lets the font derivation build.
  nixpkgs.allowedUnfreePackages = [ "corefonts" ];
  flake.nixosModules.hosts-common.imports = [ body ];
}
