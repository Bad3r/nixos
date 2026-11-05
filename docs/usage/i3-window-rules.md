# i3 floating window rules

`gui.i3.windowRules` gives each window rule a name so hosts can extend or disable it without replacing the shared list.
[window-rules.nix](../../modules/apps/i3wm/window-rules.nix) owns the shared rules.

## Identify the window

Run these commands in the i3 session and click the popup, then repeat for the main application:

```sh
xprop WM_CLASS WM_WINDOW_ROLE _NET_WM_WINDOW_TYPE _NET_WM_NAME _NET_WM_PID
xwininfo
```

Use `class` for the second `WM_CLASS` value and `instance` for the first.
Prefer a distinct `window_role` or `window_type`; add an anchored `title` pattern when the title distinguishes the popup reliably.
Criteria within one rule must all match.
i3 uses PCRE expressions, and `^` and `$` anchor a match to the whole value.

Window IDs and PIDs change between launches.
GTK bus names and object paths do not provide a reliable popup identity.
Dimensions describe the current layout and do not identify a window's purpose.
Use PIDs only to inspect the owning process when the window properties provide no stable distinction.

## Add or change a rule

In the host's [i3 module](../../modules/hosts/songbird/i3.nix), configure the owner's Home Manager rules through `metaOwner.username`:

```nix
{ metaOwner, ... }:
{
  configurations.nixos.songbird.module = {
    home-manager.users.${metaOwner.username}.gui.i3.windowRules = {
      calendar.enable = false;
      example-preferences = {
        criteria = {
          class = "(?i)^example$";
          window_role = "^preferences$";
        };
        command = "floating enable, move position center";
      };
    };
  };
}
```

Replace the example criteria with properties observed on the target application.
Omit `command` for the default `floating enable` action.
Set an existing rule's `enable` to `false` to disable that rule by name.
Use `condition` for host prerequisites, such as an application's enable option; both `condition` and `enable` must be true.

Rules run in ascending `order`, then alphabetically by name when orders match.
Keep generic floating rules before rules that resize windows, because resizing a tiled window changes its container.
Default styling runs before named rules, so a named rule can set `border none`.

Add `processArgs` when criteria alone cannot distinguish the popup.
Each listed string must equal a complete argument in the owning process's command line; arguments are case sensitive.
For example, `processArgs = [ "--preferences" ];` requires that argument, rather than a substring of another argument.
Every listed argument must occur, and the executable name does not satisfy an argument filter.

Rules without `processArgs` run through native i3 configuration.
Process rules run asynchronously in `i3-process-window-rules.service`, separately from native rules, so ordering does not synchronize the two groups.

## Default file manager

The file-manager workspace assignment follows `host.defaults.fileManager` from [default-apps.nix](../../modules/hosts/common/default-apps.nix).
[mime.nix](../../modules/xdg/mime.nix) owns the file-manager metadata used for matching.
File-manager windows advertising dialog, utility, popup, or toolbox types and roles use the generic floating rules.

## RustDesk connection manager

The incoming connection manager and main RustDesk window share their class, instance, and normal window type.
The connecting device's name in the title varies, and outgoing session titles can also match a broad RustDesk suffix pattern.
The connection manager's process runs with `--cm`, which distinguishes it without matching a particular device name.
The `rustdesk-connection-manager` rule requires that argument and leaves the main window outside its match.

The shared rule is enabled only when the host enables i3, the RustDesk app, and its systemd service.
The process-rule service is generated only when i3 and an enabled process rule are present.

## Check the running session

Evaluation and build commands do not activate window rules.
Activate the NixOS configuration through the normal rebuild workflow before checking live behavior.

Inspect process-rule service failures in the user's i3 session:

```sh
systemctl --user status i3-process-window-rules.service
journalctl --user -u i3-process-window-rules.service -b
```

Open the popup and main application separately and confirm that only the intended window floats.
Repeat with another connecting device for RustDesk so the check exercises a different peer title.
A syntax check alone does not establish which window a rule matches.

i3 command criteria: <https://i3wm.org/docs/userguide.html#command_criteria>
