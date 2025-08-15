{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.jq
        pkgs.jq-lsp
        pkgs.yq
        pkgs.xq
      ];
    };
}
