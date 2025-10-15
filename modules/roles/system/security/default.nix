{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role system.security)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  securityApps = [
    "apparmor-bin-utils"
    "apparmor-utils"
    "bitwarden-cli"
    "bitwarden-desktop"
    "fail2ban"
    "gopass"
    "gpg-tui"
    "gnupg"
    "hashcat"
    "john"
    "keepassxc"
    "lynis"
    "mosh"
    "nix-index-with-full-db"
    "pinentry-qt"
    "pwgen"
    "sops"
    "ssh-audit"
    "ssh-to-age"
    "ssh-to-pgp"
    "sshfs-fuse"
    "sudo-rs"
    "veracrypt"
    "vt-cli"
    "wireshark-qt"
    "xkcdpass"
    "yubico-piv-tool"
    "yubikey-manager"
    "yubikey-personalization"
    "burpsuite"
  ];
  roleImports = getApps securityApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "system.security" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = roleImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles.system.security = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}
