/*
  Package: bubblewrap
  Description: Unprivileged sandboxing utility for constructing constrained process namespaces.
  Homepage: https://github.com/containers/bubblewrap
  Documentation: https://github.com/containers/bubblewrap#readme
  Repository: https://github.com/containers/bubblewrap

  Summary:
    * Provides the `bwrap` launcher used to isolate application execution with explicit filesystem and namespace bindings.
    * Enables least-privilege runtime patterns such as network isolation and restricted bind-mount views.

  Options:
    --ro-bind <src> <dest>: Bind a path read-only inside the sandbox.
    --bind <src> <dest>: Bind a writable path into the sandbox namespace.
    --unshare-net: Start the process in a separate network namespace with no external network access.
*/
_:
let
  BubblewrapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bubblewrap.extended;
    in
    {
      options.programs.bubblewrap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bubblewrap.";
        };

        package = lib.mkPackageOption pkgs "bubblewrap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bubblewrap = BubblewrapModule;
}
