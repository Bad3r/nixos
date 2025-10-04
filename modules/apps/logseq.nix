{
  lib,
  ...
}:
let
  inherit (lib) escapeShellArg;

  logseqRepo = "/home/vx/git/logseq";
  logseqBinary = "${logseqRepo}/static/out/Logseq-linux-x64/Logseq";
  logseqBuilder = "/home/vx/dotfiles/.local/bin/sss-update-logseq";

  runtimePackages =
    pkgs: with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      dejavu_fonts
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk3
      harfbuzz
      krb5
      libappindicator-gtk3
      libdrm
      libnotify
      libpulseaudio
      libsecret
      libuuid
      libxkbcommon
      nspr
      nss
      pango
      pipewire
      udev
      xdg-desktop-portal
      xdg-user-dirs
      xdg-utils
      zlib

      libglvnd
      libgbm
      mesa

      pkgs.xorg.libX11
      pkgs.xorg.libXScrnSaver
      pkgs.xorg.libXcomposite
      pkgs.xorg.libXcursor
      pkgs.xorg.libXdamage
      pkgs.xorg.libXext
      pkgs.xorg.libXfixes
      pkgs.xorg.libXi
      pkgs.xorg.libXrandr
      pkgs.xorg.libXrender
      pkgs.xorg.libXtst
      pkgs.xorg.libxcb
      pkgs.xorg.libXau
      pkgs.xorg.libXdmcp
    ];
in
{
  flake.nixosModules.apps.logseq =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      rootPath = builtins.toString (config._module.args.rootPath or ../..);
      cfg = config.apps.logseq;
      ownerRaw = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] config null;
      owner = if lib.isString ownerRaw then ownerRaw else "vx";

      logseqRunner = pkgs.writeShellScript "logseq-run" ''
        set -euo pipefail
        if [ ! -x ${escapeShellArg logseqBinary} ]; then
          echo "logseq binary missing at ${logseqBinary}. Run logseq-update." >&2
          exit 1
        fi
        exec ${escapeShellArg logseqBinary} "$@"
      '';

      logseqFhs = pkgs.buildFHSEnv {
        name = "logseq-fhs";
        targetPkgs = runtimePackages;
        runScript = "${logseqRunner}";
        profile = ''
          # bind host shared memory for Chromium/Electron
          if [ -w /dev/shm ]; then
            bwrapArgs+=(--dev-bind /dev/shm /dev/shm)
          fi
        '';
      };

      logseqCommand = pkgs.writeShellScriptBin "logseq" ''
        exec ${logseqFhs}/bin/logseq-fhs "$@"
      '';

      iconSrc = "${logseqRepo}/static/resources/app/icon.png";

      logseqIcon = pkgs.runCommand "logseq-icon" { } ''
        set -euo pipefail
        dest="$out/share/icons/hicolor/512x512/apps"
        mkdir -p "$dest"
        if [ -f ${iconSrc} ]; then
          install -m644 ${iconSrc} "$dest/logseq.png"
        fi
      '';

      logseqDesktop = pkgs.writeTextFile {
        name = "logseq-desktop";
        destination = "/share/applications/logseq.desktop";
        text = ''
          [Desktop Entry]
          Name=Logseq Desktop
          Exec=logseq %U
          Terminal=false
          Type=Application
          Icon=logseq
          StartupWMClass=Logseq
          Comment=A privacy-first, open-source platform for knowledge management and collaboration.
          MimeType=x-scheme-handler/logseq;
          Categories=Office;Productivity;Utility;TextEditor;
          NoDisplay=false
        '';
      };

      logseqUpdateScript = pkgs.writeShellApplication {
        name = "logseq-update";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.util-linux
        ];
        text = ''
          set -euo pipefail

          repo=${escapeShellArg logseqRepo}
          branch=master
          remote=origin

          if [ ! -d "$repo/.git" ]; then
            echo "logseq update: skipping (repo not found at $repo)" >&2
            exit 0
          fi

          cd "$repo"

          if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "logseq update: $repo is not a git repository" >&2
            exit 1
          fi

          git fetch --quiet "$remote" "$branch" || {
            echo "logseq update: git fetch failed (offline?)" >&2
            exit 0
          }

          local_rev=$(git rev-parse HEAD)
          remote_rev=$(git rev-parse "$remote/$branch")

          if [ "$local_rev" = "$remote_rev" ]; then
            echo "logseq update: already up to date ($local_rev)"
            exit 0
          fi

          echo "logseq update: updating to $remote/$branch ($remote_rev)"
          git reset --hard "$remote/$branch"

          echo "logseq update: rebuilding via ${logseqBuilder}"
          nix develop ${escapeShellArg rootPath}#logseq --accept-flake-config --command ${escapeShellArg logseqBuilder} -f
          echo "logseq update: completed"
        '';
      };
    in
    {
      options.apps.logseq = {
        runOnActivation = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run logseq-update during system activation.";
        };

        updateTimer = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable the user-level systemd timer that rebuilds Logseq nightly.";
          };

          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "03:30";
            description = "systemd OnCalendar expression controlling when the nightly Logseq build runs.";
          };
        };

        ghq = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Provision ghq mirror integration required for local Logseq builds.";
          };

          repo = lib.mkOption {
            type = lib.types.str;
            default = "logseq/logseq";
            description = "Repository spec mirrored via ghq to back the local Logseq build.";
          };

          root = lib.mkOption {
            type = lib.types.str;
            default = "/git";
            description = "Shared ghq root path mirrored by the nightly Logseq build.";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "users";
            description = "POSIX group owning the shared ghq root.";
          };

          mode = lib.mkOption {
            type = lib.types.str;
            default = "2775";
            description = "Octal permissions applied to the ghq root (setgid by default).";
          };
        };
      };

      config =
        let
          ghqEnabled = cfg.ghq.enable && owner != null;
          updateTimerEnabled = cfg.updateTimer.enable && ghqEnabled;
          nixConfigEnv =
            "NIX_CONFIG=experimental-features = nix-command flakes pipe-operators\\n"
            + "abort-on-warn = false\\n"
            + "allow-import-from-derivation = false\\n"
            + "accept-flake-config = true\\n";
        in
        lib.mkMerge [
          (lib.mkIf cfg.ghq.enable {
            assertions = [
              {
                assertion = owner != null;
                message = "apps.logseq.ghq.enable requires config.flake.lib.meta.owner.username to be set.";
              }
            ];
          })
          {
            environment.systemPackages = [
              logseqCommand
              logseqIcon
              logseqDesktop
              logseqUpdateScript
            ];
          }
          (lib.mkIf cfg.runOnActivation {
            system.activationScripts.logseq-update = lib.stringAfter [ "users" ] ''
              if id -u vx >/dev/null 2>&1 && [ -d ${escapeShellArg logseqRepo} ]; then
                runuser -l vx -c '${logseqUpdateScript}/bin/logseq-update' || true
              fi
            '';
          })
          (lib.mkIf ghqEnabled {
            environment.systemPackages = lib.mkAfter [
              pkgs.ghq
              pkgs.git
              pkgs.coreutils
            ];

            environment.sessionVariables.GHQ_ROOT = lib.mkDefault cfg.ghq.root;

            systemd.tmpfiles.rules = lib.mkAfter [
              "d ${cfg.ghq.root} ${cfg.ghq.mode} root ${cfg.ghq.group} - -"
            ];

            home-manager.users.${owner} = {
              programs.ghqMirror = {
                root = lib.mkDefault cfg.ghq.root;
                repos = lib.mkBefore [ cfg.ghq.repo ];
              };

              systemd.user.services."logseq-build" = {
                Unit = {
                  Description = "Nightly Logseq build";
                  After = [ "ghq-mirror.service" ];
                  Wants = [ "ghq-mirror.service" ];
                };
                Service = {
                  Type = "oneshot";
                  Environment = [ nixConfigEnv ];
                  ExecStart = "${lib.escapeShellArg (logseqUpdateScript + "/bin/logseq-update")}";
                };
              };

              systemd.user.timers."logseq-build" = lib.mkIf updateTimerEnabled {
                Unit.Description = "Nightly Logseq rebuild";
                Timer = {
                  OnCalendar = cfg.updateTimer.onCalendar;
                  Persistent = true;
                };
                Install.WantedBy = [ "timers.target" ];
              };
            };
          })
        ];
    };
}
