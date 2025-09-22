{
  flake.nixosModules.apps."clojure-cli" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure ];
    };
}
