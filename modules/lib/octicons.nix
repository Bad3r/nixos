# Primer Octicons 19.42.0: an icon font for the i3bar, i3status-rust, and the shell prompt, and
# palette-colored SVG templates for the rofi menus.
# ./octicons holds the release's full SVG set; the font takes only the glyphs mapped below.
{ lib, ... }:
let
  family = "Primer Octicons";

  # Codepoint to UTF-8 string via a JSON surrogate pair.
  glyph =
    codepoint:
    let
      offset = codepoint - 65536;
      hex = n: lib.fixedWidthString 4 "0" (lib.toHexString n);
    in
    builtins.fromJSON ''"\u${hex (55296 + offset / 1024)}\u${hex (56320 + lib.mod offset 1024)}"'';

  # Supplementary Private Use Area-B, clear of the Nerd Font and Font Awesome ranges.
  blockStart = n: lib.fromHexString "100000" + n * 256;

  # Workspace N shows the Nth icon.
  workspaceIcons = [
    "terminal"
    "globe"
    "file-directory"
    "code"
    "shield-lock"
    "comment-discussion"
    "mail"
    "play"
    "tools"
    "gear"
  ];

  # i3status-rust icon keys.
  statusIcons = {
    net_wireless = "broadcast";
    net_wired = "plug";
    net_vpn = "lock";
    net_down = "arrow-down";
    net_up = "arrow-up";
    uptime = "history";
    disk_drive = "database";
    memory_mem = "stack";
    memory_swap = "arrow-switch";
    cpu = "cpu";
    cogs = "pulse";
    thermometer = "flame";
    volume = "unmute";
    volume_muted = "mute";
    webcam = "device-camera-video";
    xrandr = "device-desktop";
    unknown = "question";
    bell = "bell";
    bell-slash = "bell-slash";
    time = "clock";
    refresh = "sync";
  };

  # Starship symbols.
  promptIcons = {
    git_branch = "git-branch";
    ahead = "arrow-up";
    behind = "arrow-down";
    up_to_date = "check";
    conflicted = "alert";
    untracked = "question";
    stashed = "inbox";
    modified = "dot-fill";
    staged = "plus";
    renamed = "arrow-right";
    deleted = "dash";
    read_only = "lock";
    cmd_duration = "stopwatch";
    nix_shell = "package";
  };

  # Codepoints run in attribute name order from the block start.
  mkBlock =
    n: icons:
    lib.listToAttrs (
      lib.imap0 (
        index: key:
        lib.nameValuePair key {
          icon = icons.${key};
          codepoint = blockStart n + index;
        }
      ) (lib.attrNames icons)
    );

  workspaces = lib.imap1 (
    number: icon:
    let
      codepoint = blockStart 0 + number - 1;
    in
    {
      inherit number icon codepoint;
      # i3 workspace name; the bar strips the "N:" prefix.
      name = "${toString number}:${glyph codepoint}";
    }
  ) workspaceIcons;
  status = mkBlock 1 statusIcons;
  prompt = mkBlock 2 promptIcons;

  mappings = workspaces ++ lib.attrValues status ++ lib.attrValues prompt;
in
{
  options.flake.lib.octicons = lib.mkOption {
    type = lib.types.raw;
    description = "Primer Octicons font, its family name, the glyphs each consumer uses, and SVG templates.";
  };

  config.flake.lib.octicons = {
    inherit family glyph workspaces;
    nameOf = number: (lib.elemAt workspaces (number - 1)).name;
    status = lib.mapAttrs (_: entry: glyph entry.codepoint) status;
    prompt = lib.mapAttrs (_: entry: glyph entry.codepoint) prompt;
    unicodeRange = "U+${lib.toHexString (blockStart 0)}-U+${lib.toHexString (blockStart 3 - 1)}";

    # An Octicon as a base16 mustache template drawn in a palette slot.
    template =
      name: size: slot:
      builtins.replaceStrings [ "<svg " ] [ ''<svg fill="#{{${slot}-hex}}" '' ] (
        builtins.readFile ./octicons/${name}-${toString size}.svg
      );

    font =
      pkgs:
      pkgs.runCommand "primer-octicons"
        { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.fonttools ])) ]; }
        ''
          python3 ${./_octicons-font.py} "$out/share/fonts/opentype/primer-octicons.otf" \
            ${lib.escapeShellArg family} ${./octicons} \
            ${lib.concatMapStringsSep " " (entry: "${toString entry.codepoint}=${entry.icon}") mappings}
          install -Dm444 ${./octicons/LICENSE-primer-octicons} "$out/share/doc/primer-octicons/LICENSE"
        '';
  };
}
