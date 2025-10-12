{
  flake.nixosModules.virtualization.vmware =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.virt.vmware.enable or false;
    in
    {
      config = lib.mkIf cfg {
        virtualisation.vmware.host = {
          enable = true;
          package = pkgs.vmware-workstation;
        };

        environment.systemPackages = lib.mkAfter [ pkgs.vmware-workstation ];

        nixpkgs.allowedUnfreePackages = lib.mkAfter [
          "vmware-workstation"
        ];
      };
    };
}
