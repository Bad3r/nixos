/*
  Module: autostart-policy
  Purpose: Restrict the XDG autostart directory to entries managed by Home Manager.

  Apps occasionally drop XDG autostart desktop entries into
  ${config.xdg.configHome}/autostart outside of Home Manager (for example
  Remmina's remmina-applet.desktop after a graphical install). This module
  removes any *.desktop entry that is not a symlink into the Nix store on
  each `home-manager switch`, leaving HM-managed symlinks intact.

  Notes:
    * Runs as a Home Manager activation hook; no root required.
    * Resolves the autostart directory through `config.xdg.configHome` so
      non-default XDG layouts are honored.
    * Restricts deletions to `*.desktop` (the only filename pattern the XDG
      autostart spec recognizes); other artifacts a user may keep in the
      directory are preserved.
    * Uses `builtins.storeDir` for the symlink-target check so custom Nix
      store prefixes work the same as the default /nix/store.
    * Removals go through Home Manager's `run` helper, so
      `home-manager switch --dry-run` reports each rm without executing it.
*/
_: {
  flake.homeManagerModules.base =
    { config, lib, ... }:
    {
      home.activation.cleanForeignAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        autostartDir=${lib.escapeShellArg "${config.xdg.configHome}/autostart"}
        if [ -d "$autostartDir" ]; then
          find "$autostartDir" -mindepth 1 -maxdepth 1 -name '*.desktop' \
            \( -type f -o \( -type l ! -lname ${lib.escapeShellArg "${builtins.storeDir}/*"} \) \) \
            -print0 \
          | while IFS= read -r -d "" entry; do
              run rm -f $VERBOSE_ARG -- "$entry"
            done
        fi
      '';
    };
}
