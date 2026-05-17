# snixembed 0.3.3 (nixpkgs pin) renders SNI tray icons through GTK's
# `Gtk.StatusIcon`, which delegates raster decoding to gdk-pixbuf.
# Five defects compose into the symptom that flameshot
# ("flameshot-tray"), Remmina ("org.remmina.Remmina-status"), and
# ProtonVPN render as identical blank squares or fail to register in
# `i3bar`:
#
#   1. `src/proxyicon.vala` `set_icon_pixmap` iterates the
#      ARGB->RGBA conversion with `i += 3` over a 4-byte-per-pixel
#      buffer, garbling every pixel after the first. Fix: stride 4.
#   2. Same file, `set_icon` falls through to that broken pixmap
#      path whenever `theme.has_icon(name)` returns false. Some SNI
#      items either omit `IconPixmap` or expose it with the wrong
#      D-Bus type, and snixembed's generated Vala proxy can crash just
#      by reading the property. Fix: only use the pixmap fallback when
#      `IconPixmap` is already cached with the expected SNI array type.
#   3. ProtonVPN starts with a missing theme icon name
#      (`proton-vpn-sign`) and later switches to an absolute SVG path;
#      the guarded pixmap fallback lets Gtk render the named/file icon
#      instead of aborting while probing ProtonVPN's malformed
#      `IconPixmap`.
#   4. ProtonVPN can also expose `ToolTip` as an empty string variant
#      instead of the SNI tooltip tuple; guard tooltip reads before the
#      generated Vala proxy coerces that property.
#   5. The upstream Nix package builds against gtk3 + libdbusmenu
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
# PR #103 introduced this bridge for ProtonVPN. The source patch covers
# items 1-4; PR #195 added the librsvg wrapping in item 5. Drop the full
# override once upstream ships a release past 0.3.3 with the source fixes
# and the librsvg dependency in place.
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
