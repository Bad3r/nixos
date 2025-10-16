{
  flake.nixosModules.apps."pipewire" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pipewire ];
    };
}
