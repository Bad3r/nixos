/*
  Package: docker-compose
  Description: Define and run multi-container applications from a Compose file.
  Homepage: https://docs.docker.com/compose/
  Documentation: https://docs.docker.com/reference/cli/docker/compose/
  Repository: https://github.com/docker/compose

  Summary:
    * Starts, stops, and rebuilds the services, networks, and volumes a compose.yaml declares.
    * Talks to any Docker API socket, including the rootless Podman socket behind /run/docker.sock.

  Options:
    up -d: Create and start the services in the background.
    down: Stop and remove the services and their networks.
    logs -f: Follow the service logs.
    -f <file>: Use a specific Compose file.
*/
_:
let
  DockerComposeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."docker-compose".extended;
    in
    {
      options.programs."docker-compose".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable docker-compose.";
        };

        package = lib.mkPackageOption pkgs "docker-compose" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."docker-compose" = DockerComposeModule;
}
