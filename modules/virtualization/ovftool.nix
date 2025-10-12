_: {
  flake.nixosModules.virtualization.ovftool =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.virt.ovftool.enable or false;
      ovftoolPkg = pkgs.ovftool.override { acceptBroadcomEula = true; };
    in
    {
      config = lib.mkIf cfg {
        environment.systemPackages = lib.mkAfter [ ovftoolPkg ];

        nixpkgs.allowedUnfreePackages = lib.mkAfter [
          "ovftool"
        ];
      };
    };
}
