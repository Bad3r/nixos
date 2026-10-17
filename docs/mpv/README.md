# mpv

This directory documents how `mpv` is composed and managed in this NixOS
configuration: the NixOS app module, the Home Manager app module, the XDG
default-app integration, the MPRIS controller, and the `video-cache` shell
helper.

## Scope

The docs cover what is true today across the supported hosts and intentionally
omit host names. Each page is concise and concern-focused; cross-link the
upstream mpv manual at <https://mpv.io/manual/stable/> for canonical option
semantics. The upstream source is mirrored at `$LOCAL_MIRRORS/mpv-player-mpv`
for offline reference.

## Contents

- [Architecture](1-architecture.md): Module layering, aggregator namespaces, host gating, NixOS-to-HM activation contract.
- [Configuration](2-configuration.md): Every key the HM module writes, what it does, and why.
- [Scripts and Bindings](3-scripts-and-bindings.md): Script loading model, bundled scripts, keybindings.
- [Lua Hooks](3-lua-hooks.md): The two repo-local Lua scripts.
- [Integrations](4-integrations.md): XDG MIME defaults, MPRIS/playerctl, browser bridge, video-cache.
- [Customizing](5-customizing.md): Packages, extras, opting out per host.
- [Adding Scripts and Bindings](5-customizing-scripts.md): Per-host scripts, Lua hooks, and keybindings.
- [Troubleshooting](6-troubleshooting.md): MIME default-assertion failures, codec gaps, silent hwdec fallback.

## Navigation

- Repository docs index: [../index.md](../index.md)
- Module-system background: [../architecture/](../architecture/)
- App module style guide: [../guides/apps-module-style-guide.md](../guides/apps-module-style-guide.md)
- Custom packages style guide: [../guides/custom-packages-style-guide.md](../guides/custom-packages-style-guide.md)
