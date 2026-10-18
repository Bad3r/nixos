# App registry

The app registry is the only switch for an installed program: every app module is off until its row turns it on.
A row sets the app's `extended.enable` option, under `programs` or, for an app with a NixOS service, under `services`.

## Baseline rows

Every app module has a row in `modules/hosts/common/apps-enable.nix`, in alphabetical order within the `programs` or `services` block, at `lib.mkOverride 1100`:

```nix
programs = {
  # ...
  <tool>.extended.enable = lib.mkOverride 1100 true;
  # ...
};
```

The `apps-catalog-sync` hook (`modules/meta/hooks/apps-catalog-sync.nix`) fails on an app module that has no row.

## Host rows

A host that diverges from the baseline lists the app in the flat `appEnable` set of `modules/<host>/apps-enable.nix`, one boolean per app:

```nix
appEnable = {
  # ...
  <tool> = false;
  # ...
};
```

A nested toggle, such as `claude-code.extended.installMethods.bun.enable`, goes in the `subToggles` list of the same file as `{ path; value; }`.
`flake.lib.hostApps.mk "<host>"` builds the host module from both lists and applies every row at `lib.mkOverride 1000`, so no host file writes an override by hand.
`modules/tpnix/apps-enable.nix` shows the full shape.

`host-<host>-apps-no-noop` (`modules/hosts/common/checks.nix`) fails on a host row that repeats the baseline value.
A path resolves in `programs` first, and in `services` when only the baseline's `services` block declares it.
A path absent from both namespaces fails the host evaluation, since no switch runs that check, which reports it too.

## Prerequisites

A module that needs another app turns that app's row on with `lib.mkOverride 1050 true`, between the baseline and the host rows, so a host row still decides.
That priority is the only way a module outside the registry sets a row.
`modules/agents/claude-code/nixos.nix` turns on the language server behind each enabled LSP plugin this way.

## Package ownership

A user-facing program reaches `PATH` only through its own app module, built from that module's `package` option.
Domain, host, and hardware modules call a program by store path, or turn its row on as a prerequisite, rather than adding it to `environment.systemPackages` or `home.packages`.
`host-<host>-apps-match-registry` (`modules/hosts/common/apps-registry-checks.nix`) fails when a toggle evaluates to anything but its registry value, other than a prerequisite turning it on.
The same check fails when another module installs the package of an app whose row is off.
