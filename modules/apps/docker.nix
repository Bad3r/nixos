/*
  Package Group: docker
  Description: Docker engine CLI utilities and helpers for container workflows.
  Homepage: https://www.docker.com/
  Documentation: https://docs.docker.com/

  Summary:
    * Installs the core Docker CLI alongside compose v2 and buildx helpers.
    * Provides credential helper binaries for registries that require external auth stores.
    * Optionally enables the Docker daemon and configures user groups.

  Example Usage:
    * `docker ps` -- List running containers on the local daemon.
    * `docker compose up` -- Launch a Compose project using the v2 plugin.
    * `docker buildx bake` -- Execute cached multi-platform builds.
*/

_:
let
  DockerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.docker.extended;
      owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
    in
    {
      options.programs.docker.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Docker CLI tools.";
        };

        enableDaemon = lib.mkOption {
          type = lib.types.bool;
          default = cfg.enable;
          description = "Whether to enable the Docker daemon (virtualisation.docker).";
        };

        package = lib.mkPackageOption pkgs "docker" { };

        extraTools = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            docker-compose
            docker-buildx
            docker-credential-helpers
          ];
          description = ''
            Additional Docker tools and helpers.

            Included by default:
            - docker-compose: Multi-container orchestration
            - docker-buildx: Extended build capabilities
            - docker-credential-helpers: Credential management
          '';
          example = lib.literalExpression "with pkgs; [ docker-compose docker-buildx ]";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ] ++ cfg.extraTools;
        })
        (lib.mkIf cfg.enableDaemon (
          lib.mkMerge [
            {
              virtualisation.docker = {
                enable = true;
                enableOnBoot = false;
              };

              home-manager.extraAppImports = lib.mkAfter [ "lazydocker" ];
            }
            (lib.mkIf (owner != null) {
              users.users.${owner}.extraGroups = lib.mkAfter [ "docker" ];
            })
          ]
        ))
      ];
    };
in
{
  flake.nixosModules.apps.docker = DockerModule;
}
