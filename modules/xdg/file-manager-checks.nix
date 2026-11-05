{
  config,
  lib,
  metaOwner,
  ...
}:
let
  host = config.flake.nixosConfigurations.songbird;
  base = host.extendModules {
    modules = [
      {
        host.defaults.fileManager = lib.mkForce "nemo";
        programs.nemo.extended = {
          enable = lib.mkForce true;
          package = lib.mkForce host.pkgs.nemo;
          preview.enable = lib.mkForce true;
        };
      }
    ];
  };
  workspace = ''number "${config.flake.lib.octicons.nameOf 3}"'';
  home = system: system.config.home-manager.users.${metaOwner.username};
  selected = (home base).xsession.windowManager.i3.config.assigns.${workspace};
  dolphin = host.extendModules {
    modules = [
      {
        host.defaults.fileManager = lib.mkForce "dolphin";
        programs.dolphin.extended.enable = lib.mkForce true;
        programs.nemo.extended.enable = lib.mkForce false;
      }
    ];
  };
  noDefault = host.extendModules {
    modules = [
      {
        host.defaults.fileManager = lib.mkForce null;
        programs.nemo.extended.enable = lib.mkForce false;
      }
    ];
  };
  disabled = host.extendModules {
    modules = [
      {
        host.defaults.fileManager = lib.mkForce "nemo";
        programs.nemo.extended.enable = lib.mkForce false;
      }
    ];
  };
  mimeHandlers = system: system.config.xdg.mime.defaultApplications;
  fileManagerAssertions = builtins.filter (
    assertion: !assertion.assertion && lib.hasInfix "host.defaults.fileManager" assertion.message
  ) disabled.config.assertions;
  checks = [
    (lib.assertMsg (
      selected == [ { class = "(?i)^Nemo$"; } ]
    ) "file manager workspace must match the selected manager")
    (lib.assertMsg (
      (mimeHandlers base)."inode/directory" == "nemo.desktop"
    ) "directory MIME handler must follow the selection")
    (lib.assertMsg (
      base.config.environment.sessionVariables.FILE_MANAGER == "nemo"
    ) "FILE_MANAGER must follow the selection")
    (lib.assertMsg (
      (home base).services.udiskie.settings.program_options.file_manager
      == "${base.config.programs.nemo.extended.finalPackage}/bin/nemo"
    ) "udiskie must use the installed file manager package with its extensions")
    (lib.assertMsg (
      base.config.programs.nemo.extended.finalPackage != base.config.programs.nemo.extended.package
    ) "file manager package fixture must exercise the extension wrapper")
    (lib.assertMsg (
      (home dolphin).xsession.windowManager.i3.config.assigns.${workspace}
      == [ { class = "(?i)^dolphin$"; } ]
      && (mimeHandlers dolphin)."inode/directory" == "org.kde.dolphin.desktop"
      && dolphin.config.environment.sessionVariables.FILE_MANAGER == "dolphin"
      &&
        (home dolphin).services.udiskie.settings.program_options.file_manager
        == "${dolphin.config.programs.dolphin.extended.package}/bin/dolphin"
    ) "switching the default must update workspace, MIME, environment, and udiskie together")
    (lib.assertMsg (
      !((home noDefault).xsession.windowManager.i3.config.assigns ? ${workspace})
      && !((home noDefault).services.udiskie.settings.program_options ? file_manager)
      && !(noDefault.config.environment.sessionVariables ? FILE_MANAGER)
      && !((mimeHandlers noDefault) ? "inode/directory")
    ) "a null selection must not retain a file manager default or a hardcoded fallback")
    (lib.assertMsg (
      fileManagerAssertions != [ ] && builtins.all (assertion: !assertion.assertion) fileManagerAssertions
    ) "selecting a disabled file manager must fail the default-app assertion")
  ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.xdg-file-manager-defaults =
        assert builtins.all (passed: passed) checks;
        pkgs.runCommandLocal "xdg-file-manager-defaults" { } ''
          echo "default file manager consumers follow selection, overrides, and null" > "$out"
        '';
    };
}
