# Adding Scripts and Bindings

Scripts, Lua hooks, and keybindings change on one host without touching the shared modules; the other layers are in [customizing.md](5-customizing.md).

## Packaged Scripts

A packaged mpv script goes in `programs.mpv.extended.extraScripts` in the host's NixOS configuration.
The HM module appends that list to the script list of the mpv it builds, so the script loads at runtime with no further wiring:

```nix
{ pkgs, ... }:
{
  programs.mpv.extended.extraScripts = with pkgs.mpvScripts; [
    thumbfast
    uosc
  ];
}
```

Setting the option replaces the default list, so re-list the defaults (`thumbfast`) alongside the additions.
The scripts the HM module fixes in its own list stay active alongside them; [scripts-and-bindings.md](3-scripts-and-bindings.md) has the canonical list.
`modernz` is already an OSC replacement, so adding `uosc` stacks two OSC implementations; keep one of them.

A per-host `home-manager.sharedModules` block that sets `programs.mpv.scripts` fails Home Manager's package assertion, as the [loading model](3-scripts-and-bindings.md#script-loading-model) explains.

## Raw Lua Files

A Lua file with no nixpkgs package goes into `~/.config/mpv/scripts/` through Home Manager:

```nix
_:
{
  home-manager.sharedModules = [
    {
      xdg.configFile."mpv/scripts/my-hook.lua".text = ''
        mp.register_event("file-loaded", function()
          mp.msg.info("loaded: " .. (mp.get_property("path") or ""))
        end)
      '';
    }
  ];
}
```

This suits one-off user hooks.
The shared HM module instead packages its local scripts, `playlist_filter` and `ytdlp_cookies`, in `modules/hm-apps/mpv/scripts.nix` and adds them to the script list of the mpv it builds.

## Keybindings

```nix
_:
{
  home-manager.sharedModules = [
    {
      programs.mpv.bindings."Ctrl+r" = "playlist-shuffle";
    }
  ];
}
```

The action string comes from mpv's input command reference.
