{ inputs, ... }:
{
  flake.homeManagerModules.apps.logseq =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "logseq" "extended" "enable" ] false osConfig;
    in
    {
      imports = [ inputs.nix-logseq-git-flake.homeManagerModules.default ];

      config = lib.mkIf nixosEnabled {
        programs.logseq.themePlugin = {
          enable = true;
          # Root size scales Logseq's rem-based text (default 16px).
          extraCss = ''
            html { font-size: 14px; }
          '';
        };
      };
    };
}
