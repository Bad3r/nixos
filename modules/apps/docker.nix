/*
  Package Group: docker
  Description: Docker engine CLI utilities and helpers for container workflows.
  Homepage: https://www.docker.com/
  Documentation: https://docs.docker.com/

  Summary:
    * Installs the core Docker CLI alongside compose v2 and buildx helpers.
    * Provides credential helper binaries for registries that require external auth stores.

  Example Usage:
    * `docker ps` — List running containers on the local daemon.
    * `docker compose up` — Launch a Compose project using the v2 plugin.
    * `docker buildx bake` — Execute cached multi-platform builds.
*/

{
  config,
  lib,
  pkgs,
  ...
}:
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
    in
    {
      options.programs.docker.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Docker CLI tools.";
        };

        package = lib.mkPackageOption pkgs "docker" { };

        extraTools = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            docker-compose
            docker-buildx
            docker-credential-helpers
          ];
          description = lib.mdDoc ''
            Additional Docker tools and helpers.

            Included by default:
            - docker-compose: Multi-container orchestration
            - docker-buildx: Extended build capabilities
            - docker-credential-helpers: Credential management
          '';
          example = lib.literalExpression "with pkgs; [ docker-compose docker-buildx ]";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ] ++ cfg.extraTools;
      };
    };
in
{
  flake.nixosModules.apps.docker = DockerModule;
}
