{
  config,
  inputs,
  pkgs,
}:
let
  colors = config.lib.stylix.colors.withHashtag;
  ui = import ../../stylix/_vscode-dark-2026.nix;
  syntaxTheme = config.lib.stylix.colors {
    template = builtins.readFile "${inputs.stylix}/modules/bat/base16-stylix.tmTheme.mustache";
    extension = ".tmTheme";
  };
  scopes = {
    "codex.accent".foreground = ui."menu.selectionBorder";
    "codex.ui.prompt" = {
      foreground = ui."foreground";
      background = ui."quickInput.background";
    };
    "codex.ui.surface" = {
      foreground = ui."foreground";
      background = ui."menu.background";
    };
    "codex.ui.history" = {
      foreground = colors.base05;
      background = ui."chat.requestBubbleBackground";
    };
    "codex.ui.plan" = {
      foreground = ui."foreground";
      background = ui."editorWidget.background";
    };
    "codex.ui.selection" = {
      foreground = ui."quickInputList.focusForeground";
      background = ui."quickInputList.focusBackground";
    };
    "codex.ui.muted".foreground = colors.base04;
    "codex.ui.border".foreground = ui."input.border";
    "codex.ui.success".foreground = ui."gitDecoration.addedResourceForeground";
    "codex.ui.warning".foreground = ui."list.warningForeground";
    "codex.ui.error".foreground = ui."errorForeground";
    "markup.inserted" = {
      foreground = colors.base0B;
      background = ui."diffEditor.insertedLineBackground";
    };
    "markup.deleted" = {
      foreground = colors.base0F;
      background = ui."diffEditor.removedLineBackground";
    };
  };
in
pkgs.runCommand "codex-stylix-theme"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    scopesFile = pkgs.writeText "codex-ui-scopes.json" (builtins.toJSON scopes);
  }
  ''
    python3 - ${syntaxTheme} "$scopesFile" "$out" <<'PY'
    import json
    import plistlib
    import sys

    with open(sys.argv[1], "rb") as source:
        theme = plistlib.load(source)
    with open(sys.argv[2]) as source:
        scopes = json.load(source)
    theme["settings"].extend(
        {"scope": scope, "settings": settings}
        for scope, settings in scopes.items()
    )
    with open(sys.argv[3], "wb") as output:
        plistlib.dump(theme, output, sort_keys=False)
    PY
  ''
