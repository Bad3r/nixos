{
  nixpkgs.allowedUnfreePackages = [
    "temurin-bin-24"
  ];

  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        clojure
        clojure-lsp
        temurin-bin-24
      ];
    };
}
