{
  config,
  lib,
  ...
}:
let
  flakeAttrs = config.flake or { };
  nixosModules = flakeAttrs.nixosModules or { };
  roleHelpers = config._module.args.nixosRoleHelpers or { };
  sanitizeModule =
    module:
    if module == null then
      null
    else if builtins.isAttrs module then
      builtins.removeAttrs module [ "flake" ]
    else
      module;
  rawResolveRole = roleHelpers.getRole or (_: null);
  resolveRoleOption =
    name:
    let
      candidateEval = builtins.tryEval (rawResolveRole name);
      candidate = if candidateEval.success then candidateEval.value else null;
      namePath = lib.splitString "." name;
      rolePath = [ "roles" ] ++ namePath;

      tryGetRole =
        attrs:
        if lib.hasAttrByPath rolePath attrs then
          let
            valueEval = builtins.tryEval (lib.getAttrFromPath rolePath attrs);
          in
          if valueEval.success then valueEval.value else null
        else
          null;

      fromNixosModules = tryGetRole nixosModules;
      fromFlakeModules = tryGetRole (config.flake.nixosModules or { });
    in
    if candidate != null then
      candidate
    else if fromNixosModules != null then
      fromNixosModules
    else if fromFlakeModules != null then
      fromFlakeModules
    else if lib.hasAttr name fallbackRoleModules then
      lib.getAttr name fallbackRoleModules
    else
      null;

  baseWorkstationRoles = [
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

  hasRole = roleHelpers.hasRole or (_: false);
  optionalRoles = lib.optional (hasRole "system.vendor.system76") "system.vendor.system76";

  workstationRoles = baseWorkstationRoles ++ optionalRoles;

  fallbackRoleModules = { };
  baseImport = [ ];
  hmModules = flakeAttrs.homeManagerModules or { };
  hmGuiModule = lib.attrByPath [ "gui" ] null hmModules;
  hmAppModules = hmModules.apps or { };
  resolvedRoles = map (name: {
    inherit name;
    module = resolveRoleOption name;
    sanitized =
      let
        value = resolveRoleOption name;
      in
      if value == null then null else sanitizeModule value;
  }) workstationRoles;

  availableRoleModules = map (role: if role.sanitized != null then role.sanitized else role.module) (
    lib.filter (role: role.sanitized != null || role.module != null) resolvedRoles
  );

  missingRoleNames = map (role: role.name) (
    lib.filter (role: role.sanitized == null && role.module == null) resolvedRoles
  );

  importsValue = baseImport ++ availableRoleModules;
in
{
  flake.nixosModules.workstation = {
    imports =
      if missingRoleNames == [ ] then
        importsValue
      else
        lib.warn (
          "Skipping unavailable workstation roles: " + lib.concatStringsSep ", " missingRoleNames
        ) importsValue;
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
            throw ("Unknown Home Manager app '" + name + "' referenced by workstation role");
        extraAppModules = map getAppModule extraNames;
      in
      {
        # Append the GUI bundle for all Home Manager users while keeping the
        # imports built by modules/home-manager/nixos.nix (which collect
        # extraAppImports like flameshot).
        home-manager.sharedModules = lib.mkAfter ([ hmGuiModule ] ++ extraAppModules);
      }
    );
  };
}
