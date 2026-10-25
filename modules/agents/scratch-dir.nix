# The agent scratch root: harness temp, sessions/<root session id> (each agent
# shell's TMPDIR), and named topic dirs, which the sweep never deletes.
{
  config,
  lib,
  metaOwner,
  ...
}:
let
  mountGateFor =
    config.flake.lib.nixos._localMirrorsMountGate
      or (throw "modules/git/mirror-root.nix no longer exports flake.lib.nixos._localMirrorsMountGate");
  inherit (config.flake.lib.agents) scratchDir;
in
{
  options.flake.lib.agents.scratchDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "/data/agents";
    description = "Agent scratch root: the launchers' TMPDIR, parent of the per-session shell TMPDIRs, and home of topic dirs.";
  };

  config.flake.nixosModules.hosts-common =
    {
      config,
      pkgs,
      utils,
      ...
    }:
    let
      owner = metaOwner.username;
      ownerHome = config.users.users.${owner}.home;
      sweep = pkgs.writeShellApplication {
        name = "agents-scratch-sweep";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.jq
          pkgs.trash-cli
        ];
        text = ''
          scratch=${lib.escapeShellArg scratchDir}
          sessions="$scratch/sessions"

          # Codex keeps no live-session registry; its sessions rely on mtime alone.
          live=" "
          for entry in ${lib.escapeShellArg "${ownerHome}/.claude/sessions"}/*.json; do
            [ -e "$entry" ] || continue
            pid="$(jq -r '.pid // empty' "$entry")"
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
              live+="$(jq -r '.sessionId // empty' "$entry") "
            fi
          done

          idleFor() {
            [ -z "$(find "$1" -newermt "-$2 days" -print -quit)" ]
          }

          if [ -d "$sessions" ]; then
            for dir in "$sessions"/*/; do
              [ -d "$dir" ] || continue
              id="$(basename "$dir")"
              case "$live" in *" $id "*) continue ;; esac
              if idleFor "$dir" 7; then
                echo "trashing idle session dir ''${dir%/}"
                trash-put -- "''${dir%/}"
              fi
            done
          fi

          for entry in "$scratch"/nix-shell.* "$scratch"/nix-develop-* "$scratch"/pyright-* "$scratch"/tmp.*; do
            if { [ -f "$entry" ] || [ -d "$entry" ]; } && [ ! -L "$entry" ] && idleFor "$entry" 2; then
              echo "trashing tool temp $entry"
              trash-put -- "$entry"
            fi
          done

          for dir in "$scratch"/*/; do
            name="$(basename "$dir")"
            case "$name" in sessions | claude-* | codex-* | node-compile-cache | nix-shell.* | nix-develop-* | pyright-*) continue ;; esac
            if idleFor "$dir" 60; then
              echo "topic dir idle for 60+ days: $dir"
            fi
          done
        '';
      };
      mountGate = mountGateFor scratchDir config.fileSystems utils;
    in
    {
      systemd = {
        # A mount-gated oneshot, not tmpfiles: /data is nofail, so tmpfiles would
        # create the directory on the root filesystem when the volume is absent.
        services.agents-scratch-dir = {
          description = "Provision the agent scratch directory";
          wantedBy = [ "multi-user.target" ];
          inherit (mountGate) after unitConfig;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = utils.escapeSystemdExecArgs [
              "${pkgs.coreutils}/bin/install"
              "-d"
              "-m"
              "0700"
              "-o"
              owner
              "-g"
              "users"
              scratchDir
            ];
          };
        };

        # Session dirs idle 7 days and stale tool temp go to the trash; topic dirs only get logged.
        services.agents-scratch-sweep = {
          description = "Sweep idle agent session scratch";
          inherit (mountGate) after unitConfig;
          serviceConfig = {
            Type = "oneshot";
            User = owner;
            Group = "users";
            ExecStart = lib.getExe sweep;
          };
        };
        timers.agents-scratch-sweep = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };
      };
    };
}
