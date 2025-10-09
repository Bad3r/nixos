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
  flake.nixosModules.apps.docker =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        docker
        docker-compose
        docker-buildx
        docker-credential-helpers
      ];
    };
}
