# Claude Code theme after VS Code Dark 2026 (2026-dark.json); Stylix slots
# where the palette has the color, VS Code values where it has none.
{ lib, colors }:
let
  channels =
    hex:
    map (i: lib.fromHexString (builtins.substring i 2 hex)) [
      1
      3
      5
    ];
  toHex =
    rgb:
    "#"
    + lib.concatMapStrings (
      c:
      let
        h = lib.toLower (lib.toHexString c);
      in
      if builtins.stringLength h == 1 then "0${h}" else h
    ) rgb;
  # fg at alpha (0-255, as in VS Code's #rrggbbaa) over bg.
  over =
    fg: alpha: bg:
    toHex (
      lib.zipListsWith (f: b: builtins.floor (b + (f - b) * alpha / 255.0 + 0.5)) (channels fg) (
        channels bg
      )
    );
  shimmer = c: over colors.base07 89 c;

  editor = colors.base00; # editor.background
  accent = "#3994bc"; # focusBorder
  link = "#48a0c7"; # textLink.foreground
  success = "#73c991"; # gitDecoration.addedResourceForeground
  warning = "#e5ba7d"; # list.warningForeground
  error = "#f48771"; # errorForeground
  chart = {
    red = "#ef8773";
    orange = "#cd861a";
    yellow = "#e0b97f";
    green = "#86cf86";
    blue = "#57a3f8";
    purple = "#ad80d7";
  };
  insertedLine = over "#347d39" 38 editor; # diffEditor.insertedLineBackground
  removedLine = over "#c93c37" 38 editor; # diffEditor.removedLineBackground
in
{
  name = "VS Code Dark 2026";
  base = "dark";
  overrides = {
    text = colors.base05;
    inverseText = editor;
    inactive = colors.base04;
    inactiveShimmer = colors.base05;
    subtle = "#555555"; # disabledForeground
    promptBorder = "#333536"; # input.border
    promptBorderShimmer = colors.base04;
    suggestion = link;
    remember = link;
    professionalBlue = link;
    briefLabelYou = link;
    ide = colors.base0D;
    background = colors.base0C;
    permission = accent;
    permissionShimmer = shimmer accent;
    claudeBlue_FOR_SYSTEM_SPINNER = accent;
    claudeBlueShimmer_FOR_SYSTEM_SPINNER = shimmer accent;
    claude = colors.base09;
    claudeShimmer = shimmer colors.base09;
    briefLabelClaude = colors.base09;
    clawd_body = colors.base09;
    clawd_background = editor;
    autoAccept = colors.base0E;
    autoAcceptShimmer = shimmer colors.base0E;
    skill = colors.base0E;
    merged = colors.base0E;
    effortUltra = colors.base0E;
    bashBorder = colors.base0F;
    planMode = colors.base0C;
    fastMode = colors.base09;
    fastModeShimmer = shimmer colors.base09;
    inherit success error warning;
    warningShimmer = shimmer warning;

    diffAdded = insertedLine;
    diffRemoved = removedLine;
    diffAddedDimmed = over "#347d39" 19 editor;
    diffRemovedDimmed = over "#c93c37" 19 editor;
    diffAddedWord = over "#57ab5a" 77 insertedLine; # diffEditor.insertedTextBackground
    diffRemovedWord = over "#f47067" 77 removedLine; # diffEditor.removedTextBackground

    userMessageBackground = over "#ffffff" 19 editor; # chat.requestBubbleBackground
    userMessageBackgroundHover = over "#ffffff" 34 editor; # chat.requestBubbleHoverBackground
    composerSidebarBackground = colors.base01; # sideBar.background
    selectionBg = over "#276782" 221 editor; # editor.selectionBackground
    bashMessageBackgroundColor = "#242526"; # textCodeBlock.background
    memoryBackgroundColor = "#1e3a47"; # inputValidation.infoBackground
    rate_limit_fill = accent;
    rate_limit_empty = "#333536"; # input.border

    red_FOR_SUBAGENTS_ONLY = chart.red;
    orange_FOR_SUBAGENTS_ONLY = chart.orange;
    yellow_FOR_SUBAGENTS_ONLY = chart.yellow;
    green_FOR_SUBAGENTS_ONLY = chart.green;
    blue_FOR_SUBAGENTS_ONLY = chart.blue;
    purple_FOR_SUBAGENTS_ONLY = chart.purple;
    pink_FOR_SUBAGENTS_ONLY = colors.base0F;
    cyan_FOR_SUBAGENTS_ONLY = colors.base0C;
    chromeYellow = chart.yellow;

    rainbow_red = chart.red;
    rainbow_orange = chart.orange;
    rainbow_yellow = chart.yellow;
    rainbow_green = chart.green;
    rainbow_blue = chart.blue;
    rainbow_indigo = colors.base0D;
    rainbow_violet = chart.purple;
    rainbow_red_shimmer = shimmer chart.red;
    rainbow_orange_shimmer = shimmer chart.orange;
    rainbow_yellow_shimmer = shimmer chart.yellow;
    rainbow_green_shimmer = shimmer chart.green;
    rainbow_blue_shimmer = shimmer chart.blue;
    rainbow_indigo_shimmer = shimmer colors.base0D;
    rainbow_violet_shimmer = shimmer chart.purple;
  };
}
