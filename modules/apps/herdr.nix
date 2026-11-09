/*
  Package: herdr
  Description: Terminal workspace manager for AI coding agents.
  Homepage: https://herdr.dev
  Documentation: https://herdr.dev/docs/configuration/
  Repository: https://github.com/herdrdev/herdr

  Notes:
    * No analytics uploader was found in the pinned 0.9.5 source.
    * The launcher disables Herdr diagnostic logging with HERDR_LOG=off.
    * Home Manager disables background release and detection-manifest checks.
    * Agents and user-installed plugins retain their own network behavior.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.herdr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.herdr.extended;
      upstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
    in
    {
      options.programs.herdr.extended = {
        enable = lib.mkEnableOption "Herdr terminal workspaces for coding agents";
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.symlinkJoin {
            name = "herdr-${upstream.version}";
            inherit (upstream) version meta;
            paths = [ upstream ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram "$out/bin/herdr" --set HERDR_LOG off
            '';
          };
          defaultText = lib.literalExpression "privacy-wrapped inputs.llm-agents.packages.\${system}.herdr";
          description = "The Herdr package to use, wrapped by default to disable diagnostic logging.";
        };
        settings = lib.mkOption {
          inherit (pkgs.formats.toml { }) type;
          default = { };
          description = "Herdr configuration. Background release and detection-manifest checks are always disabled in the managed configuration.";
        };
      };
      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };

  flake.homeManagerModules.apps.herdr =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = osConfig.programs.herdr.extended;
      colors = config.lib.stylix.colors.withHashtag;
      vscode = import ../stylix/_vscode-dark-2026.nix;
      # VS Code Dark 2026 (2026-dark.json) over every Herdr palette token.
      theme.custom = {
        accent = vscode."statusBarItem.prominentBackground";
        panel_bg = colors.base01; # panel.background, editorGroupHeader.tabsBackground
        sidebar_bg = colors.base01; # sideBar.background
        active_row_bg = vscode."list.inactiveSelectionBackground";
        selection_bg = vscode."list.focusBackground";
        surface0 = vscode."quickInput.background";
        surface1 = vscode."input.border";
        surface_dim = colors.base02; # widget.border
        overlay0 = colors.base04; # descriptionForeground, tab.inactiveForeground
        overlay1 = colors.base05; # editorLineNumber.activeForeground
        text = vscode."list.activeSelectionForeground";
        subtext0 = vscode.foreground;
        mauve = vscode."charts.purple";
        green = vscode."gitDecoration.addedResourceForeground";
        yellow = vscode."list.warningForeground";
        red = vscode.errorForeground;
        blue = vscode."charts.blue";
        teal = colors.base0C;
        peach = vscode."charts.orange";
      };
      settings = lib.recursiveUpdate { inherit theme; } cfg.settings // {
        update = (cfg.settings.update or { }) // {
          version_check = false;
          manifest_check = false;
        };
      };
    in
    {
      config = lib.mkIf cfg.enable {
        xdg.configFile."herdr/config.toml".source =
          (pkgs.formats.toml { }).generate "herdr-config.toml"
            settings;
      };
    };
}
