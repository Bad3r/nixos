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
          description = "Herdr configuration. The managed configuration always skips onboarding and disables background release and detection-manifest checks.";
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
      # VS Code Dark 2026 (2026-dark.json) over every Herdr palette token, with
      # desaturated blues. Kitty applies background_opacity only to cells
      # with the default background, so "reset" keeps the chrome translucent.
      theme.custom = {
        accent = "#7b9aac"; # statusBarItem.prominentBackground at 23% saturation
        panel_bg = "reset";
        sidebar_bg = "reset";
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
        blue = "#8aa6c4"; # charts.blue at 33% saturation
        teal = "#7fa9b2"; # base0C at 25% saturation
        peach = vscode."charts.orange";
      };
      assets = "${
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr.src
      }/src/integration/assets";
      settings =
        lib.recursiveUpdate {
          inherit theme;
          ui.toast.delivery = "terminal";
        } cfg.settings
        // {
          # Completing onboarding writes this key into the read-only config.
          onboarding = false;
          update = (cfg.settings.update or { }) // {
            version_check = false;
            manifest_check = false;
          };
        };
    in
    {
      config = lib.mkIf cfg.enable {
        # The shared agent hooks (modules/agents/hooks/herdr-agent-session.nix)
        # run the integration scripts from the store. Herdr reads integration
        # status from the version marker at these paths, and `herdr integration
        # install` fails on the read-only links instead of registering a second
        # hook.
        home.file.".claude/hooks/herdr-agent-state.sh".source = "${assets}/claude/herdr-agent-state.sh";
        xdg.configFile = {
          "codex/herdr-agent-state.sh".source = "${assets}/codex/herdr-agent-state.sh";
          "herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr-config.toml" settings;
        };
      };
    };
}
