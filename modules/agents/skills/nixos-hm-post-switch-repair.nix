_:
let
  skillBody = ''
    ## When To Use

    Use when a NixOS switch completed but user-level Home Manager artifacts are
    stale or degraded in an integrated setup (Home Manager runs as a NixOS
    module, not the standalone `home-manager` CLI).

    Triggers:

    - A `~/.config/*` symlink points at an old or missing `/nix/store/...`
      generation.
    - User systemd units report `Unit to trigger vanished` or fail after
      `./build.sh`, `nh os switch`, or `nixos-rebuild switch`.
    - The user asks for a real Home Manager activation on top of an integrated
      Home Manager setup.

    Non-goals:

    - Standalone `home-manager` CLI workflows outside the integrated NixOS
      module setup.
    - System-level unit repairs unrelated to the user manager or Home Manager
      generation links.

    If the argument names a specific user unit, target that unit; otherwise
    default to the unit named in the symptom the user reported.

    ## Gather Context

    1. Confirm the setup is integrated Home Manager (the generation is built by
       the system switch, not by a separate `home-manager switch`).
    2. Capture the active Home Manager generation root:

    ```bash
    readlink -f ~/.local/state/home-manager/gcroots/current-home
    ```

    3. Check the drifted symlink or unit state, for example:

    ```bash
    readlink ~/.config/<app>/<file>
    systemctl --user status <unit>
    ```

    4. Only if the above is inconclusive, inspect the journal around the switch
       window:

    ```bash
    journalctl --user -n 150 --no-pager
    ```

    ## Repair Procedure

    1. Reapply the current Home Manager generation directly by running its
       activation script:

    ```bash
    "$(readlink -f ~/.local/state/home-manager/gcroots/current-home)/activate"
    ```

    2. Refresh user-manager state after activation:

    ```bash
    systemctl --user daemon-reload
    systemctl --user reset-failed
    ```

    3. If a timer or service was degraded or missing, re-enable it (substitute
       the reported unit):

    ```bash
    systemctl --user enable --now <unit>
    ```

    4. If files keep drifting after activation, resolve the ownership conflict:
       check whether a competing dotfile manager (for example Dotbot) owns the
       same path, then remove or disable that entry so Home Manager is the sole
       owner, and rerun the activation script.

    ## Efficiency Plan

    1. Inspect `current-home` and one failing artifact before any broader log
       dive.
    2. Run one activation pass, then one systemd recovery pass; only read deeper
       logs if failures persist.
    3. Stop once both the link target and the unit state verify cleanly.

    ## Pitfalls And Fixes

    - Symptom: a config file links to a nonexistent store path.
      - Likely cause: a competing owner re-symlinked the directory after the
        Home Manager run.
      - Fix: remove the overlap and rerun Home Manager activation.

    - Symptom: `<unit>: Unit to trigger vanished`.
      - Likely cause: the user manager re-executed during the switch with an
        incomplete Home Manager reactivation.
      - Fix: activate Home Manager, `daemon-reload`, `reset-failed`, then enable
        the unit.

    - Symptom: invoking `nixos-activation.service` does nothing for user links.
      - Likely cause: wrong activation layer (that service does not own
        user-level Home Manager links).
      - Fix: run the generated Home Manager `activate` script instead.

    ## Verification Checklist

    - The repaired symlink resolves into the active Home Manager generation when
      Home Manager owns the path.
    - `systemctl --user is-active <unit>` returns `active`.
    - `systemctl --user is-failed` does not list the recovered units.
  '';
in
{
  flake.lib.agents._internal.skills.raw.nixos-hm-post-switch-repair = {
    name = "nixos-hm-post-switch-repair";
    title = "NixOS Home Manager Post-Switch Repair";
    description = "Reapply integrated Home Manager activation and recover drifted user systemd units or symlinks after a NixOS switch.";
    body = skillBody;

    codex = {
      openaiYaml.interface = {
        display_name = "HM Post-Switch Repair";
        short_description = "Recover user HM links and units after a NixOS switch";
        default_prompt = "Reapply the integrated Home Manager generation and recover drifted user systemd units or symlinks after a NixOS switch.";
      };
    };

    claude = {
      frontmatter = {
        "allowed-tools" = "Bash, Read, Grep";
        "argument-hint" = "[optional target unit]";
      };
    };
  };
}
