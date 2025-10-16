{
  flake.nixosModules.apps."clojure" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."clojure" ];
    };
}
