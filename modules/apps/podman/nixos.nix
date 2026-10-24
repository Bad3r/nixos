/*
  Package: podman
  Description: Daemonless OCI container engine with a Docker-compatible CLI and API.
  Homepage: https://podman.io/
  Documentation: https://docs.podman.io/
  Repository: https://github.com/containers/podman

  Summary:
    * Runs containers rootless as the owner; `docker` is a shim for the podman CLI.
    * Links /run/docker.sock to the owner's rootless API socket, so act, lazydocker, and
      docker-compose find it without DOCKER_HOST.

  Options:
    run --device nvidia.com/gpu=all: Expose the NVIDIA GPU through CDI.
    --runtime runsc: Run a container under gVisor.
    compose: Run docker-compose against the Podman API.

  Notes:
    * DOCKER_HOST cannot come from environment.sessionVariables: pam_env runs before pam_systemd
      sets XDG_RUNTIME_DIR.
    * The compat API ignores the requested runtime, so only the podman CLI (and the `docker`
      shim) can select runsc.
    * The rootful API socket stays off; virtualisation.podman.autoPrune prunes only the root
      store, so a Home Manager timer prunes the rootless one.
*/
_:
let
  PodmanModule =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      cfg = config.programs.podman.extended;
      ownerUid = toString config.users.users.${metaOwner.username}.uid;
    in
    {
      options.programs.podman.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Podman.";
        };

        package = lib.mkPackageOption pkgs "podman" { };
      };

      config = lib.mkIf cfg.enable {
        programs."docker-compose".extended.enable = lib.mkOverride 1050 true;

        virtualisation.podman = {
          enable = true;
          inherit (cfg) package;
          dockerCompat = true;
          extraRuntimes = [
            pkgs.runc
            pkgs.gvisor
          ];
        };

        virtualisation.containers = {
          containersConf.settings = {
            network = {
              default_subnet = "172.20.0.0/24";
              default_subnet_pools = [
                {
                  base = "172.20.0.0/14";
                  size = 24;
                }
              ];
            };
            engine = {
              compose_providers = [ (lib.getExe config.programs."docker-compose".extended.package) ];
              compose_warning_logs = false;
              # Rootless runsc fails without it: systemd demands interactive auth for its cgroup.
              runtimes_flags.runsc = [ "ignore-cgroups" ];
            };
          };

          # Docker's short-name behaviour; with one entry Podman never prompts.
          registries.settings.unqualified-search-registries = [ "docker.io" ];
        };

        systemd.sockets.podman.wantedBy = lib.mkForce [ ];

        systemd.tmpfiles.settings.podman-docker-socket."/run/docker.sock"."L+".argument =
          "/run/user/${ownerUid}/podman/podman.sock";
      };
    };
in
{
  flake.nixosModules.apps.podman = PodmanModule;
}
