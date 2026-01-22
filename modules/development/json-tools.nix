{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.jq
        pkgs.jq-lsp
      ];
    };
}
