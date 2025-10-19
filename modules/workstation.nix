{
  config,
  lib,
  ...
}:
let
  flakeAttrs = config.flake or { };
  nixosModules = flakeAttrs.nixosModules or { };
  roleHelpers = config._module.args.nixosRoleHelpers or { };
  rawResolveRole = roleHelpers.getRole or (_: null);
  resolveRoleOption =
    name:
    let
      candidate = rawResolveRole name;
      namePath = lib.splitString "." name;
      rolePath = [ "roles" ] ++ namePath;

      tryGetRole =
        attrs:
        if lib.hasAttrByPath rolePath attrs then
          let
            value = lib.getAttrFromPath rolePath attrs;
          in
          value
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

  resolveRole =
    name:
    let
      result = resolveRoleOption name;
    in
    if result != null then
      result
    else
      throw ("Unknown role '" + name + "' referenced by flake.nixosModules.workstation");
  appHelpers = config._module.args.nixosAppHelpers or { };
  rawAppHelpers = (config.flake.lib.nixos or { }) // appHelpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' referenced by workstation role");
  getApp = rawAppHelpers.getApp or fallbackGetApp;
  getApps = rawAppHelpers.getApps or (names: map getApp names);
  workstationRoles = [
    "xserver"
    "cli"
    "files"
    "file-sharing"
    "dev"
    "media"
    "net"
    "productivity"
    "ai-agents"
    "gaming"
    "security"
    "cloudflare"
  ];
  pythonRoleModules = getApps [
    "python"
    "uv"
    "ruff"
    "pyright"
  ];
  goRoleModules = getApps [
    "go"
    "gopls"
    "golangci-lint"
    "delve"
  ];
  rustRoleModules = getApps [
    "rustc"
    "cargo"
    "rust-analyzer"
    "rustfmt"
    "rust-clippy"
  ];
  cljRoleModules = getApps [
    "clojure-cli"
    "clojure-lsp"
    "leiningen"
    "babashka"
    "pixman"
  ];
  devLanguageModules = pythonRoleModules ++ goRoleModules ++ rustRoleModules ++ cljRoleModules;

  fallbackRoleModules = {
    "file-sharing" = {
      imports = getApps [
        "qbittorrent"
        "localsend"
        "rclone"
        "rsync"
        "nicotine"
        "filen-cli"
        "filen-desktop"
        "dropbox"
      ];
    };
  };
  baseImport =
    if rawResolveRole "base" != null then
      [ (resolveRole "base") ]
    else if lib.hasAttrByPath [ "base" ] nixosModules then
      [ (lib.getAttrFromPath [ "base" ] nixosModules) ]
    else
      throw "flake.nixosModules.base missing while constructing workstation bundle";
  hmModules = flakeAttrs.homeManagerModules or { };
  hmGuiModule = lib.attrByPath [ "gui" ] null hmModules;
  hmAppModules = hmModules.apps or { };
  resolvedRoles = map (name: {
    inherit name;
    module = resolveRoleOption name;
  }) workstationRoles;

  availableRoleModules = map (role: role.module) (
    lib.filter (role: role.module != null) resolvedRoles
  );

  missingRoleNames = map (role: role.name) (lib.filter (role: role.module == null) resolvedRoles);

  importsValue = baseImport ++ availableRoleModules ++ devLanguageModules;
in
{
  flake.nixosModules.workstation = {
    imports =
      if missingRoleNames == [ ] then
        importsValue
      else
        throw (
          "workstation bundle requires roles that failed to resolve: "
          + lib.concatStringsSep ", " missingRoleNames
        );
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
