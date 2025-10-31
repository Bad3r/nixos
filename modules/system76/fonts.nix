{
  lib,
  inputs,
  ...
}:
let
  fontArchive = inputs.secrets + "/fonts/monolisa.tar.zst";
  secretExists = builtins.pathExists fontArchive;
  secretName = "fonts/monolisa.archive";
  secretRuntimePath = "/run/secrets/fonts/monolisa.archive";
  fontInstallDir = "/var/lib/fonts/monolisa";
in
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      config = lib.mkMerge [
        {
          fonts = {
            enableDefaultPackages = true;
            packages = with pkgs; [
              noto-fonts
              noto-fonts-cjk-sans
              noto-fonts-color-emoji
              liberation_ttf
              font-awesome
              nerd-fonts.symbols-only
            ];

            fontconfig = {
              defaultFonts = {
                serif = [
                  "MonoLisa"
                  "Symbols Nerd Font"
                  "Symbols Nerd Font Mono"
                  "Font Awesome 6 Free"
                  "Font Awesome 6 Brands"
                ];
                sansSerif = [
                  "MonoLisa"
                  "Symbols Nerd Font"
                  "Symbols Nerd Font Mono"
                  "Font Awesome 6 Free"
                  "Font Awesome 6 Brands"
                ];
                monospace = [
                  "MonoLisa"
                  "Symbols Nerd Font Mono"
                  "Symbols Nerd Font"
                  "Font Awesome 6 Free"
                  "Font Awesome 6 Brands"
                ];
                emoji = [
                  "Noto Color Emoji"
                  "Symbols Nerd Font"
                  "Symbols Nerd Font Mono"
                ];
              };
            };
          };
        }
        (lib.optionalAttrs secretExists {
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
            description = "Install MonoLisa fonts from encrypted archive";
            wantedBy = [ "multi-user.target" ];
            after = [ "sops-install-secrets.service" ];
            requires = [ "sops-install-secrets.service" ];
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

              install -d -m 0755 "${fontInstallDir}"
              find "${fontInstallDir}" -mindepth 1 -exec rm -rf {} +

              cp -R "$tmpdir"/. "${fontInstallDir}/"

              find "${fontInstallDir}" -type d -exec chmod 0755 {} +
              find "${fontInstallDir}" -type f -exec chmod 0644 {} +

              fc-cache -f "${fontInstallDir}"
            '';
          };

          fonts.fontconfig.localConf = ''
            <?xml version="1.0"?>
            <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
            <fontconfig>
              <dir>${fontInstallDir}</dir>
            </fontconfig>
          '';
        })
      ];
    };
}
