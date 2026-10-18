# Architecture

mpv is composed in two cooperating layers: a NixOS app module that owns the
app row, its options, and the system-wide extras, and a Home Manager app module
that installs mpv and writes the user-level configuration.

## Layered Composition

- **NixOS app module**
  - Location: `modules/apps/mpv/nixos.nix`
  - Namespace: `flake.nixosModules.apps.mpv`
  - Role: Declares the row and its options, and adds the extras to `environment.systemPackages` when `programs.mpv.extended.enable` is true.
- **HM app module**
  - Location: `modules/apps/mpv/home.nix`
  - Namespace: `flake.homeManagerModules.apps.mpv`
  - Role: Installs `programs.mpv.extended.package` rewrapped with a script list (packaged scripts plus two repo-local Lua scripts), and writes `mpv.conf`, `input.conf`, and a `script-opts` file, when the NixOS layer is enabled.

## Aggregator Namespaces

There are two namespaces:

- `flake.nixosModules.apps.mpv`
- `flake.homeManagerModules.apps.mpv`

For background on how the two namespaces behave differently see
[../architecture/03-nixos-modules.md](../architecture/03-nixos-modules.md) and
[../architecture/04-home-manager.md](../architecture/04-home-manager.md).

## Option Namespace

The NixOS module declares `programs.mpv.extended` with the standard options
this repo uses for app modules:

- `programs.mpv.extended.enable`
  - Type: `bool`
  - Default: `false`
  - Purpose: Master switch. Controls system install and HM gating.
- `programs.mpv.extended.package`
  - Type: package option
  - Default: `pkgs.mpv`
  - Purpose: The mpv package the HM module rewraps and installs.
- `programs.mpv.extended.extraScripts`
  - Type: list of packages
  - Default: `[ pkgs.mpvScripts.thumbfast ]`
  - Purpose: Declares mpv script packages. The HM module reads this list via `osConfig` and rewraps the row's package with it, adding `--script=` flags so the scripts load at runtime. These packages are not added to `environment.systemPackages`.
- `programs.mpv.extended.extras.defaultShaders.enable`
  - Type: bool, default `true`
  - Purpose: Installs `pkgs.mpv-shim-default-shaders` via `environment.systemPackages`.
- `programs.mpv.extended.extras.openInMpv.enable`
  - Type: bool, default `true`
  - Purpose: Installs `pkgs.open-in-mpv` via `environment.systemPackages`.
- `programs.mpv.extended.extras.jellyfinShim.enable`
  - Type: bool, default `false`
  - Purpose: Installs `pkgs.jellyfin-mpv-shim` via `environment.systemPackages`. Opt-in.
- `programs.mpv.extended.extraPackages`
  - Type: list of packages, default `[]`
  - Purpose: Additive escape hatch for packages not covered by `extras.*`.

The HM layer does not introduce a parallel option namespace; it consumes the
NixOS `enable` flag through `osConfig` (see [Activation contract](#activation-contract)
below) and otherwise drives the upstream Home Manager `programs.mpv` module
directly.

### Package install contract

Only the HM module installs mpv, through `home.packages` and `programs.mpv.finalPackage`.
It sets `programs.mpv.package` to `programs.mpv.extended.package` rewrapped with `override { scripts = ...; }`, which adds the `--script=` flags.
Upstream `programs.mpv.scripts` stays empty: setting it rewraps `pkgs.mpv`, and Home Manager then asserts that `programs.mpv.package` is the default.
The NixOS module installs only the extras.

### Activation contract

The HM module reads the NixOS-side `enable` flag rather than declaring its own.
The pattern at `modules/apps/mpv/home.nix`:

```nix
{ osConfig, lib, pkgs, ... }:
let
  nixosEnabled = lib.attrByPath [ "programs" "mpv" "extended" "enable" ] false osConfig;
in
{
  config = lib.mkIf nixosEnabled {
    programs.mpv = {
      enable = true;
      # ...
    };
  };
}
```

Two consequences follow:

- The HM body, including `programs.mpv.enable = true`, is gated by the NixOS
  flag. Disabling mpv on a host (`programs.mpv.extended.enable = false`)
  drops both layers in lockstep, so the user profile is never left with an
  active `programs.mpv` block pointing at a stale config.
- `lib.attrByPath` tolerates the option being absent on hosts that do not
  import `modules/apps/mpv/nixos.nix` at all, defaulting to `false` rather than
  throwing.

The common baseline pins app-enable bits with `lib.mkOverride 1100` in
`modules/hosts/common/apps-enable.nix`, which sets
`mpv.extended.enable = true`. Per-host override files such as
`modules/tpnix/apps-enable.nix` layer `lib.mkOverride 1000` on top, so the
host value wins over the baseline.
Priority `1100` sits between `mkDefault` (priority `1000`) and
`mkOptionDefault` (priority `1500`), so the baseline overrides the option's
declared default while still yielding to per-host overrides and to explicit
user-level definitions (priority `100`).

## Where to Look Next

- For the full set of values written into `mpv.conf`: [configuration.md](2-configuration.md).
- For how scripts are loaded and which ones ship enabled: [scripts-and-bindings.md](3-scripts-and-bindings.md).
- For MIME wiring, MPRIS, browser integration, and the playlist helper:
  [integrations.md](4-integrations.md).
