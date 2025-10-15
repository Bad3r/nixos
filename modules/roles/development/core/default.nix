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
      throw ("Unknown NixOS app '" + name + "' (role development.core)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  coreApps = [
    # editors
    "neovim"
    "vim"
    "glow"
    # build tools
    "cmake"
    "gcc"
    "gnumake"
    "pkg-config"
    "biome"
    "nixfmt-rfc-style"
    "nixfmt"
    "ShellCheck"
    "prettier"
    "shfmt"
    "treefmt"
    # JSON/YAML/tools
    "yq"
    "jnv"
    "tokei"
    "hyperfine"
    "git-filter-repo"
    "forgit"
    "clippy"
    "Image-ExifTool"
    # debugging
    "gdb"
    "valgrind"
    "strace"
    "ltrace"
    "ent"
    # Node toolchains and managers
    "nodejs"
    "nodejs_24"
    "nodejs_22"
    "yarn"
    "nrm"
    # FHS-based dev tools
    "vscodeFhs"
    "vscode"
    "kiroFhs"
  ];
  coreImports = getApps coreApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "development.core" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = coreImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles.development.core = {
    metadata = {
      canonicalAppStreamId = "Development";
      categories = [ "Development" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}
