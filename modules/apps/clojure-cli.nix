{
  flake.nixosModules.apps.clojure-cli =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure ];
    };
}
