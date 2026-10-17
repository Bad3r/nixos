# Customizing

The mpv setup extends, overrides, and opts out per host or per user without touching the shared modules.
The core principle is to change the smallest scope that achieves the goal.

- [Adding scripts and bindings](5-customizing-scripts.md): packaged scripts, raw Lua files, and keybindings.

## Choosing the Right Layer

- Toggle a bundled extra (shaders, browser bridge, Jellyfin shim): `programs.mpv.extended.extras.<name>.enable`.
- Install a tool not covered by the named extras: `programs.mpv.extended.extraPackages`, which is additive.
- Add an mpv script that loads at startup: `programs.mpv.extended.extraScripts`, which the HM module builds into the user's mpv.
- Change a single mpv config key for one host: a per-host `home-manager.sharedModules` block setting `programs.mpv.config.<key>`.
- Add or change a keybinding: a per-host `home-manager.sharedModules` block setting `programs.mpv.bindings.<key>`.
- Replace the mpv package itself: `programs.mpv.extended.package` per host.
- Add a one-off Lua snippet: `xdg.configFile."mpv/scripts/<name>.lua"` in Home Manager.
- Disable mpv entirely on a host: `mpv = false` in the host's app rows, as [App registry](../guides/apps-module-registry.md) describes.

## Overriding a Configuration Key

mpv's HM module exposes `programs.mpv.config` as a free-form attrset, so any mpv option name works.
To override a single value on one host:

```nix
_:
{
  home-manager.sharedModules = [
    {
      programs.mpv.config = {
        volume = 80;          # raise default volume
        gpu-context = "wayland"; # force Wayland context on mixed-display setups
      };
    }
  ];
}
```

## Replacing the mpv Package

The HM module builds the user's mpv from `programs.mpv.extended.package`, so setting it per host swaps in a custom build without a `pkgs.mpv` overlay:

```nix
{ pkgs, ... }:
{
  programs.mpv.extended.package = pkgs.mpv.override {
    mpv-unwrapped = pkgs.mpv-unwrapped.override { /* ... */ };
  };
}
```

## Adding mpv-Adjacent Tools

Three bundled extras have named enable options:

- `extras.defaultShaders.enable` (default `true`): `mpv-shim-default-shaders`, the shader presets.
- `extras.openInMpv.enable` (default `true`): `open-in-mpv`, the browser-to-mpv bridge.
- `extras.jellyfinShim.enable` (default `false`): `jellyfin-mpv-shim`, for casting from Jellyfin clients.

Toggle any of them per host:

```nix
{ ... }:
{
  programs.mpv.extended.extras.jellyfinShim.enable = true;
  programs.mpv.extended.extras.openInMpv.enable = false;
}
```

Packages the named options do not cover go in `extraPackages`, whose entries are additive, so the named extras need no re-listing:

```nix
{ pkgs, ... }:
{
  programs.mpv.extended.extraPackages = with pkgs; [ mpv-inhibit-gnome ];
}
```

## Adding a User-Specific Override

A change for one user only goes inside that user's home-manager block rather than the shared module:

```nix
{ metaOwner, ... }:
{
  home-manager.users.${metaOwner.username}.programs.mpv.config.volume = 100;
}
```

That suits taste-driven knobs such as volume and OSC behavior.

## Where to Look Next

- For the list of keys that can be overridden: [configuration.md](2-configuration.md).
- For what scripts and bindings are active by default: [scripts-and-bindings.md](3-scripts-and-bindings.md).
- For known issues that may require a customization: [troubleshooting.md](6-troubleshooting.md).
