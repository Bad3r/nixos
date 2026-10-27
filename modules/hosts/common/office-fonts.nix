{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  parts = [
    "00"
    "01"
  ];
  archivePart = part: secretsRoot + "/fonts/windows-office.tar.zst.part-${part}";
  archiveExists = builtins.all (part: builtins.pathExists (archivePart part)) parts;
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
in
{
  nixpkgs.allowedUnfreePackages = [ "vista-fonts" ];
  flake.nixosModules.hosts-common.imports = [
    (
      {
        config,
        hostName,
        pkgs,
        ...
      }:
      let
        runtimeReady = (hostsRegistry.${hostName} or { }).sopsRuntimeReady or false;
        installReady = archiveExists && runtimeReady;
        installDir = "/var/lib/fonts/windows-office";
        archiveFiles = map archivePart parts;
        installSecretsDeps = sopsInstallSecretsDeps config;
      in
      {
        assertions = [
          {
            assertion = !(builtins.any (part: builtins.pathExists (archivePart part)) parts) || archiveExists;
            message = "Windows/Office font archive is incomplete; initialize the secrets submodule at its pinned commit.";
          }
        ];
        fonts.packages = [ pkgs.vista-fonts ];
        fonts.fontconfig.confPackages = lib.optional installReady (
          pkgs.writeTextDir "etc/fonts/conf.d/52-windows-office.conf" ''
            <?xml version="1.0"?>
            <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
            <fontconfig>
              <dir>${installDir}/fonts</dir>
              <!-- Candara Light reports normal weight, which otherwise lets it
                   win regular Candara requests over the vista-fonts face. -->
              <match target="scan">
                <test name="family" compare="eq">
                  <string>Candara Light</string>
                </test>
                <edit name="weight" mode="assign"><const>light</const></edit>
              </match>
            </fontconfig>
          ''
        );

        warnings = lib.optional (
          archiveExists && !runtimeReady
        ) "Windows/Office secret fonts are disabled on ${hostName} until sopsRuntimeReady is set.";

        systemd.services = lib.optionalAttrs installReady {
          windows-office-fonts = {
            description = "Install Windows and Office fonts from encrypted archive";
            wantedBy = [ "multi-user.target" ];
            after = installSecretsDeps;
            requires = installSecretsDeps;
            restartTriggers = archiveFiles;
            path = with pkgs; [
              coreutils
              findutils
              gnutar
              gnugrep
              sops
              zstd
              fontconfig
            ];
            environment = {
              FONT_INSTALL_DIR = installDir;
              SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
            };
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              Group = "root";
              UMask = "0077";
              Restart = "on-failure";
            };
            script = ''
              fontArchives=( ${lib.escapeShellArgs (map toString archiveFiles)} )
            ''
            + builtins.readFile ./_office-fonts-install.sh;
          };
        };
      }
    )
  ];
}
