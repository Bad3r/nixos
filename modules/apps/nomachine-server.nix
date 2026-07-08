/*
  Package: nomachine-server
  Description: NoMachine remote desktop server for accepting NX client connections.
  Homepage: https://www.nomachine.com/
  Documentation: https://kb.nomachine.com/DT04U00278
  Repository: nil

  Summary:
    * Runs the NoMachine server daemon for remote physical desktop access over the NX protocol.
    * Seeds NoMachine runtime state from the upstream Linux tarball while keeping package files immutable.

  Options:
    --status: Show NoMachine server and node status.
    --startup: Start the server daemon and wait until it is ready.
    --shutdown: Stop the server daemon.
    --help: Show server and node command help.

  Notes:
    * Uses services namespace because NoMachine runs as a system daemon.
    * The upstream installer mutates /etc, /usr, PAM, polkit, systemd, and firewall state. This module exposes the same payload through NixOS-managed users, files, tmpfiles, firewall rules, and systemd service definitions.
    * The systemd unit mirrors the upstream scripts/systemd/nxserver.service (User=nx, Type=simple, KillMode=process, SuccessExitStatus="0 SIGTERM", Restart=always): the daemon deliberately runs as the unprivileged nx account, and nxexec stays foreground so Type=simple is correct (no forking).
    * The daemon is NOT yet functional end-to-end on NixOS: the upstream installer marks nxexec, nxfsm, and /etc/NX/nxserver setuid-root (nxsetup lines ~6225/10001/10012) so the nx-user daemon can escalate for PAM auth and per-user session spawn. The read-only, nosuid Nix store cannot carry those bits through the ${serverRoot}/bin store symlink, so client authentication and session startup need setuid wrappers wired through security.wrappers pointing ${serverRoot}/bin/{nxexec,nxfsm} at /run/wrappers/bin. Tracked as follow-up; verifying it requires a live deploy plus a client connection.
    * tmpfiles `C ${serverRoot}/etc` seeds the mutable config once; it is not refreshed when cfg.package changes. After a package update that ships new etc defaults, wipe ${serverRoot}/etc so the daemon picks up upstream changes.
    * NoMachine v8 and newer use TCP port 4000 and UDP port 4000 for NX protocol connections.
    * Package is unfree and must remain in `nixpkgs.allowedUnfreePackages`.
*/
_:
let
  NomachineServerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services."nomachine-server".extended;
      stateRoot = "/var/lib/nomachine";
      serverRoot = "${stateRoot}/NX";
      nxHome = "${stateRoot}/nx";

      nomachine-server = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "nomachine-server";
        version = pkgs.nomachine-client.version;

        src = pkgs.nomachine-client.src;

        nativeBuildInputs = with pkgs; [
          autoPatchelfHook
          file
          makeWrapper
        ];

        buildInputs = with pkgs; [
          alsa-lib
          cups
          dbus
          fontconfig
          freetype
          jsoncpp
          libGL
          libdrm
          libice
          libpulseaudio
          libsm
          stdenv.cc.cc.lib
          zlib
          libx11
          libxscrnsaver
          libxau
          libxcb
          libxcomposite
          libxcursor
          libxdamage
          libxdmcp
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxt
          libxtst
        ];

        postUnpack = ''
          for archive in NX/etc/NX/server/packages/*.tar.gz; do
            tar xf "$archive"
          done

          rm -rf NX/home NX/var
          rm -rf NX/share/src/nxusb-legacy
          rm -f NX/bin/nxusbd-legacy NX/lib/libnxusb-legacy.so
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/NX" "$out/bin"
          cp -r bin etc lib scripts share "$out/NX/"

          cp "$out/NX/etc/server-debian.cfg.sample" "$out/NX/etc/server.cfg"
          cp "$out/NX/etc/node-debian.cfg.sample" "$out/NX/etc/node.cfg"

          substituteInPlace "$out/NX/etc/server.cfg" \
            --replace-fail "#UpdateFrequency 172800" "UpdateFrequency 0" \
            --replace-fail "#NXTCPPort 4000" "NXTCPPort 4000" \
            --replace-fail "#NXUDPPort 4000" "NXUDPPort 4000" \
            --replace-fail "#EnableUPnP none" "EnableUPnP none" \
            --replace-fail "#StartHTTPDaemon Automatic" "StartHTTPDaemon Manual" \
            --replace-fail "#ClientConnectionMethods NX" "ClientConnectionMethods NX" \
            --replace-fail "#EnableFirewallConfiguration 1" "EnableFirewallConfiguration 0" \
            --replace-fail "#EnableWebPlayer 1" "EnableWebPlayer 0"

          substituteInPlace "$out/NX/etc/node.cfg" \
            --replace-fail "#DisplayServerExtraOptions \"\"" "DisplayServerExtraOptions \"-nolisten tcp\""

          makeWrapper "$out/NX/bin/nxserver" "$out/bin/nxserver"
          makeWrapper "$out/NX/bin/nxnode" "$out/bin/nxnode"

          runHook postInstall
        '';

        dontBuild = true;
        dontStrip = true;

        meta = pkgs.nomachine-client.meta // {
          inherit (finalAttrs) version;
          description = "NoMachine remote desktop server";
          mainProgram = "nxserver";
          maintainers = pkgs.nomachine-client.meta.maintainers or [ ];
          platforms = [ "x86_64-linux" ];
        };
      });
    in
    {
      options.services."nomachine-server".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nomachine-server.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = nomachine-server;
          defaultText = lib.literalExpression "nomachine-server package built from pkgs.nomachine-client.src";
          description = "The nomachine-server package to use.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to open the NoMachine NX TCP and UDP ports (4000) in the
            firewall on every interface. Off by default: NX is a remote-login
            surface, so opening it is a deliberate per-host decision. Prefer
            scoping the ports to a trusted interface (e.g. tailscale0) in the
            host firewall module instead of enabling this blanket opener.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        users.groups.nx = { };
        users.users.nx = {
          isSystemUser = true;
          group = "nx";
          home = nxHome;
          createHome = true;
          shell = "/etc/NX/nxnode";
          ignoreShellProgramCheck = true;
        };

        environment.etc = {
          "NX/nxserver".source = "${cfg.package}/NX/scripts/etc/nxserver";
          "NX/nxnode".source = "${cfg.package}/NX/scripts/etc/nxnode";
          "NX/server/localhost/server.cfg".text = ''
            ServerRoot = "${serverRoot}"
            NXUserHome = "${nxHome}/.nx"
          '';
          "NX/server/localhost/node.cfg".text = ''
            NodeRoot = "${serverRoot}"
          '';
        };

        # The upstream pam.d/nx is "auth include su" and pam.d/nxlimits is a
        # bare "session optional pam_limits.so". Dropping those verbatim into
        # /etc/pam.d fails on NixOS: generated PAM files reference modules by
        # absolute store path, so a bare pam_limits.so never resolves. Declare
        # the services so NixOS emits store-path-correct stacks (nx = standard
        # unix password auth, matching upstream's delegation to su; nxlimits =
        # session-only stack that carries pam_limits).
        security.pam.services = {
          nx = { };
          nxlimits = { };
        };

        systemd.tmpfiles.rules = [
          "d ${stateRoot} 0755 root root - -"
          "d ${serverRoot} 0755 root root - -"
          "L+ ${serverRoot}/bin - - - - ${cfg.package}/NX/bin"
          "L+ ${serverRoot}/lib - - - - ${cfg.package}/NX/lib"
          "L+ ${serverRoot}/scripts - - - - ${cfg.package}/NX/scripts"
          "L+ ${serverRoot}/share - - - - ${cfg.package}/NX/share"
          "C ${serverRoot}/etc - - - - ${cfg.package}/NX/etc"
          "d ${serverRoot}/var 0750 nx nx - -"
          "d ${serverRoot}/var/db 0750 nx nx - -"
          "d ${serverRoot}/var/db/node 0750 nx nx - -"
          "d ${serverRoot}/var/log 0750 nx nx - -"
          "d ${serverRoot}/var/run 0750 nx nx - -"
          "d ${nxHome} 0700 nx nx - -"
          "d ${nxHome}/.nx 0700 nx nx - -"
        ];

        networking.firewall = lib.mkIf cfg.openFirewall {
          allowedTCPPorts = [ 4000 ];
          allowedUDPPorts = [ 4000 ];
        };

        systemd.services.nomachine-server = {
          description = "NoMachine Server daemon";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "sshd.service"
          ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            bash
            coreutils
            findutils
            gawk
            gnugrep
            gnused
            iproute2
            nettools
            openssh
            procps
            util-linux
            xauth
          ];
          serviceConfig = {
            User = "nx";
            Group = "nx";
            ExecStart = "/etc/NX/nxserver --daemon";
            KillMode = "process";
            Restart = "always";
            SuccessExitStatus = "0 SIGTERM";
          };
        };
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "nomachine-client"
    "nomachine-server"
  ];
  flake.nixosModules.apps."nomachine-server" = NomachineServerModule;
}
