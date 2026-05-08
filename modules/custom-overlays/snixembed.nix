# snixembed 0.3.3 (nixpkgs pin) renders SNI tray icons through GTK's
# `Gtk.StatusIcon`, which delegates raster decoding to gdk-pixbuf.
# Three defects compose into the symptom that flameshot
# ("flameshot-tray"), Remmina ("org.remmina.Remmina-status"), and
# ProtonVPN render as identical blank squares in `i3bar`:
#
#   1. `src/proxyicon.vala` `set_icon_pixmap` iterates the
#      ARGB->RGBA conversion with `i += 3` over a 4-byte-per-pixel
#      buffer, garbling every pixel after the first. Fix: stride 4.
#   2. Same file, `set_icon` falls through to that broken pixmap
#      path whenever `theme.has_icon(name)` returns false, even for
#      SNI items with no `IconPixmap`, replacing the named icon Gtk
#      would render with a corrupted pixmap. Fix: widen the
#      early-return guard so the pixmap path is reachable only when
#      the theme misses AND the SNI item supplied real pixmap bytes.
#   3. The upstream Nix package builds against gtk3 + libdbusmenu
#      without `wrapGAppsHook3` and without `librsvg` in scope, so
#      `GDK_PIXBUF_MODULE_FILE` is unset at runtime and gdk-pixbuf
#      lacks the SVG loader. Modern icon themes (Qogir, Adwaita,
#      Papirus, hicolor) ship status/panel icons exclusively as SVG;
#      gdk-pixbuf cannot decode them and Gtk falls back to
#      `image-missing`, which is the actual symptom seen on this
#      host. Fix: wrap with `wrapGAppsHook3` and add `librsvg` so
#      the resulting `GDK_PIXBUF_MODULE_FILE` cache registers
#      `libpixbufloader-svg.so`.
#
# PR #103 introduced this bridge for ProtonVPN; PR #193 added the
# source patch for items 1 + 2; PR #195 added item 3. Drop the full
# override once upstream ships a release past 0.3.3 with both the
# source fixes and the librsvg dependency in place.
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.snixembed.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: prev: {
            snixembed = prev.snixembed.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [
                ../../packages/snixembed/icon-resolution.patch
              ];
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                final.wrapGAppsHook3
              ];
              buildInputs = (old.buildInputs or [ ]) ++ [
                final.librsvg
              ];
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays.snixembed = Overlay;
}
