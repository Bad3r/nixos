_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.lefthook-ensure-sops = pkgs.writeShellApplication {
        name = "lefthook-ensure-sops";
        runtimeInputs = [ pkgs.pre-commit-hook-ensure-sops ];
        text = # bash
          ''
            [ $# -eq 0 ] && exit 0
            exec pre-commit-hook-ensure-sops "$@"
          '';
      };
    };
}
