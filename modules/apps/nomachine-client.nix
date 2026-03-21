/*
  Package: nomachine-client
  Description: NoMachine remote desktop client for NX sessions.
  Homepage: https://www.nomachine.com/
  Documentation: https://www.nomachine.com/documents

  Summary:
    * Provides the `nxplayer` GUI client for connecting to NoMachine remote desktops and published applications.
    * Reuses saved `.nxs` session profiles so connection, display, and authentication settings can be launched repeatedly.

  Options:
    nxplayer: Launch the graphical client and manage saved connections.
    --session <file.nxs>: Start a connection from a saved session profile.
    --hide: Hide the client window for floating custom sessions until the session disconnects.

  Notes:
    * Package is unfree and must remain in `nixpkgs.allowedUnfreePackages`.
*/
_:
let
  NomachineClientModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nomachine-client".extended;
    in
    {
      options.programs."nomachine-client".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nomachine-client.";
        };

        package = lib.mkPackageOption pkgs "nomachine-client" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "nomachine-client" ];
  flake.nixosModules.apps."nomachine-client" = NomachineClientModule;
}
