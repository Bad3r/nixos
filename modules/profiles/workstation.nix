{
  config,
  lib,
  ...
}:
let
  flakeAttrs = config.flake or { };
  nixosModules = flakeAttrs.nixosModules or { };
  roleHelperArgs = config._module.args.nixosRoleHelpers or { };
  roleHelpers = (config.flake.lib.nixos.roles or { }) // roleHelperArgs;
  rawGetRole = roleHelpers.getRole or (_: null);

  fallbackGetRole =
    name:
    let
      attrPath = [ "roles" ] ++ lib.splitString "." name;
    in
    lib.attrByPath attrPath null nixosModules;

  resolveRole =
    name:
    let
      attempt = builtins.tryEval (rawGetRole name);
      candidate = if attempt.success then attempt.value else null;
    in
    if candidate != null then candidate else fallbackGetRole name;

  workstationRoles = [
    "system.base"
    "system.display.x11"
    "system.storage"
    "system.security"
    "system.nixos"
    "system.virtualization"
    "utility.cli"
    "utility.monitoring"
    "utility.archive"
    "development.core"
    "development.python"
    "development.go"
    "development.rust"
    "development.clojure"
    "development.ai"
    "audio-video.media"
    "network.tools"
    "network.remote-access"
    "network.sharing"
    "network.vendor.cloudflare"
    "office.productivity"
    "game.launchers"
  ];

  resolvedRoles = map (name: {
    inherit name;
    module = resolveRole name;
  }) workstationRoles;

  availableModules = map (role: role.module) (lib.filter (role: role.module != null) resolvedRoles);

  missingNames = map (role: role.name) (lib.filter (role: role.module == null) resolvedRoles);

  importsValue = availableModules;

  hmModules = flakeAttrs.homeManagerModules or { };
  hmGuiModule = lib.attrByPath [ "gui" ] null hmModules;
  hmAppModules = hmModules.apps or { };

  missingWarning =
    if missingNames == [ ] then
      ""
    else
      "profiles.workstation missing roles: " + lib.concatStringsSep ", " missingNames;

  workstationModule = {
    imports = if missingNames == [ ] then importsValue else lib.warn missingWarning importsValue;

    config = lib.mkIf (hmGuiModule != null) (
      let
        extraNames = lib.attrByPath [ "home-manager" "extraAppImports" ] [ ] config;
        getAppModule =
          name:
          let
            module = lib.attrByPath [ name ] null hmAppModules;
          in
          if module != null then
            module
          else
            throw ("Unknown Home Manager app '" + name + "' referenced by workstation profile");
        extraAppModules = map getAppModule extraNames;
      in
      {
        home-manager.sharedModules = lib.mkAfter ([ hmGuiModule ] ++ extraAppModules);
      }
    );
  };
in
{
  flake.nixosModules.profiles.workstation = workstationModule;
  flake.profiles.workstation = workstationModule;
  _module.args.nixosProfiles.workstation = workstationModule;
}
