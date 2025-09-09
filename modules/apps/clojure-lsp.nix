{
  flake.modules.nixos.apps.clojure-lsp =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure-lsp ];
    };
}
