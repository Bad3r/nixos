{
  flake.nixosModules.apps.clojure-lsp =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure-lsp ];
    };
}
