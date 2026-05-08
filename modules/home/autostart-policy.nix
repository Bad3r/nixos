/*
  Module: autostart-policy
  Purpose: Restrict ~/.config/autostart to entries managed by Home Manager.

  Apps occasionally drop XDG autostart desktop entries into
  ~/.config/autostart outside of Home Manager (for example Remmina's
  remmina-applet.desktop after a graphical install). This module wipes any
  entry that is not a symlink into /nix/store on each `home-manager switch`,
  leaving HM-managed symlinks intact.

  Notes:
    * Runs as a Home Manager activation hook; no root required.
    * Only inspects the immediate contents of ~/.config/autostart; nested
      directories are skipped.
    * Removes regular files and symlinks that point outside /nix/store.
*/
_: {
  flake.homeManagerModules.base =
    { lib, ... }:
    {
      home.activation.cleanForeignAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        autostartDir="$HOME/.config/autostart"
        if [ -d "$autostartDir" ]; then
          find "$autostartDir" -mindepth 1 -maxdepth 1 \
            \( -type f -o \( -type l ! -lname '/nix/store/*' \) \) \
            -printf 'autostart-policy: removing %p\n' \
            -delete
        fi
      '';
    };
}
