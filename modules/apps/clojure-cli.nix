{
  flake.modules.nixos.apps.clojure-cli =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure ];
    };
}
