{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        clojure
        clojure-lsp
        leiningen
        babashka
      ];
    };
}
