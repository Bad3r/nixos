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
            exit 0
          fi

          git reset --hard "$remote/$branch"

          nix develop ${escapeShellArg rootPath}#logseq --accept-flake-config --command ${escapeShellArg logseqBuilder} -f
        '';
      };
    in
    {
      environment.systemPackages = [
        logseqCommand
        logseqUpdateScript
      ];

      system.activationScripts.logseq-update = lib.stringAfter [ "users" ] ''
        if id -u vx >/dev/null 2>&1 && [ -d ${escapeShellArg logseqRepo} ]; then
          runuser -l vx -c '${logseqUpdateScript}/bin/logseq-update' || true
        fi
      '';
    };
}
