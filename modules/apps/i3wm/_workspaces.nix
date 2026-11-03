# i3 workspaces: one Octicon per workspace number, rendered by a generated icon font.
{ lib }:
let
  # Workspace N shows the Nth icon from ./workspace-icons.
  icons = [
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

  # Supplementary Private Use Area-B, clear of the Nerd Font and Font Awesome ranges.
  firstCodepoint = lib.fromHexString "100000";

  # Codepoint to UTF-8 string via a JSON surrogate pair.
  glyph =
    codepoint:
    let
      offset = codepoint - 65536;
      hex = n: lib.fixedWidthString 4 "0" (lib.toHexString n);
    in
    builtins.fromJSON ''"\u${hex (55296 + offset / 1024)}\u${hex (56320 + lib.mod offset 1024)}"'';

  fontFamily = "Workspace Octicons";

  workspaces = lib.imap1 (number: icon: rec {
    inherit number icon;
    codepoint = firstCodepoint + number - 1;
    name = "${toString number}:${glyph codepoint}";
  }) icons;
in
{
  inherit fontFamily workspaces;

  nameOf = number: (lib.elemAt workspaces (number - 1)).name;

  font =
    pkgs:
    pkgs.runCommand "workspace-octicons"
      { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.fonttools ])) ]; }
      ''
        python3 ${./_workspace-font.py} "$out/share/fonts/opentype/workspace-octicons.otf" \
          ${lib.escapeShellArg fontFamily} ${./workspace-icons} \
          ${lib.concatMapStringsSep " " (ws: "${toString ws.codepoint}=${ws.icon}") workspaces}
      '';
}
