{
  flake.nixosModules.apps."clojure-lsp" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure-lsp ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure-lsp ];
    };
}
