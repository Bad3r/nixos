{
  flake.nixosModules.apps."nvme-cli" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nvme-cli ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nvme-cli ];
    };
}
