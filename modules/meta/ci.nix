{
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib) nixos;
  inherit (config.flake.lib.xdg) desktopFiles;
  inherit (config.flake) nixosConfigurations;
  helpers = nixos;

  # Generate desktop file validation check for a specific host
  mkHostDesktopFilesCheck =
    hostName: hostConfig: pkgs:
    let
      inherit (hostConfig.config.system76) defaults;

      # Build check commands for each configured default
      checkCommands = lib.flatten (
        lib.mapAttrsToList (
          catName: catDesktopFiles:
          let
            selectedApp = defaults.${catName};
          in
          # Guard: only proceed if a default is configured for this category
          if selectedApp == null then
            [ ]
          else
            let
              appInfo = catDesktopFiles.${selectedApp};
              moduleName = appInfo.module;
              desktopFile = appInfo.desktop;
              isEnabled = hostConfig.config.programs.${moduleName}.extended.enable;
              pkg = hostConfig.config.programs.${moduleName}.extended.package;
            in
            lib.optional isEnabled ''
              if [ ! -f "${pkg}/share/applications/${desktopFile}" ]; then
                echo "ERROR: Desktop file '${desktopFile}' not found in package '${pkg.name}'"
                echo "       Expected at: ${pkg}/share/applications/${desktopFile}"
                echo "       Host: ${hostName}, Category: ${catName}, App: ${selectedApp}"
                exit 1
              fi
              echo "✓ ${hostName}/${catName}: ${desktopFile} found in ${pkg.name}"
            ''
        ) desktopFiles
      );
    in
    pkgs.runCommand "desktop-files-valid-${hostName}" { } ''
      echo "Validating desktop files for host '${hostName}'..."
      echo ""
      ${lib.concatStringsSep "\n" checkCommands}
      echo ""
      echo "All desktop file validations passed for '${hostName}'."
      touch $out
    '';
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        # Verify flake.lib.nixos helpers exist
        helpers-exist =
          let
            result =
              if (helpers ? getApp) && (helpers ? getApps) && (helpers ? getAppOr) && (helpers ? hasApp) then
                "ok"
              else
                throw "missing helper(s) under config.flake.lib.nixos";
          in
          builtins.seq result (pkgs.runCommand "helpers-exist-ok" { } "touch $out");
      }
      # Generate desktop-files-valid check for each Linux nixosConfiguration
      # XDG mimeapps is Linux-specific; Darwin uses Launch Services
      // lib.mapAttrs' (
        hostName: hostConfig:
        lib.nameValuePair "desktop-files-valid-${hostName}" (
          mkHostDesktopFilesCheck hostName hostConfig pkgs
        )
      ) (lib.filterAttrs (_: hostConfig: hostConfig.pkgs.stdenv.isLinux) nixosConfigurations);
    };
}
