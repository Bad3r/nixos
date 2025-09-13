Home Manager Aggregator (flake.homeManagerModules)

Overview

- Aggregation schema lives under `flake.homeManagerModules` with mergeable types:
  - `base`: deferred module (merged across files)
  - `gui`: deferred module (merged across files)
  - `apps`: attrset of deferred modules keyed by app name (merged by key)
- Roles are data (not modules) under `flake.lib.homeManager.roles` and are resolved to concrete modules at the glue layer.

Defining modules

- Base module (merged):
  flake.homeManagerModules.base = \_: {
  home.sessionVariables.TZ = "Asia/Riyadh";
  };

- GUI module (merged):
  flake.homeManagerModules.gui = { pkgs, ... }: {
  home.packages = [ pkgs.libnotify ];
  };

- App modules (per-name, merged by key):
  flake.homeManagerModules.apps.alacritty = \_: {
  programs.alacritty.enable = true;
  };

Roles as data

- Declare roles in `flake.lib.homeManager.roles` (data only):
  {
  cli = [ "bat" "eza" "fzf" ];
  terminals = [ "kitty" "alacritty" "wezterm" ];
  }

Resolving roles to modules (glue)

- At the NixOS→HM glue, map role names to app modules and append them to the user imports:
  let
  roles = config.flake.lib.homeManager.roles or { };
  getApp = name: config.flake.homeManagerModules.apps.${name};
    roleToModules = role: map getApp (roles.${role} or [ ]);
  in
  users.${user}.imports = [ ... ] ++ (roleToModules "cli") ++ (roleToModules "terminals");

Notes

- Always provide module functions (`_: { ... }`) for `base`, `gui`, and each `apps.<name>`.
- Avoid dot-assignments like `flake.homeManagerModules.base.home.* = …`; use a module value instead.
- Keep tests hermetic: do not import the aggregator directly in HM checks.
