{ lib, ... }:
{
  # Canonicalize i3 keybinding names for consistency across modules.
  # Expose helpers under: config.flake.lib.homeManager.i3
  flake.lib.homeManager.i3 =
    let
      normalizeKey =
        key:
        let
          parts = lib.splitString "+" key;
          canon =
            part:
            let
              lower = lib.toLower part;
            in
            if lib.hasPrefix "$" part then
              part
            else if (lower == "control" || lower == "ctrl" || lower == "ctl") then
              "Ctrl"
            else if lower == "shift" then
              "Shift"
            else if (lower == "alt" || lower == "mod1") then
              "Alt"
            else if (lower == "super" || lower == "win" || lower == "mod4") then
              "super"
            else if (lower == "enter" || lower == "return") then
              "Return"
            else if (lower == "esc" || lower == "escape") then
              "Escape"
            else if (lower == "pgup" || lower == "prior") then
              "Prior"
            else if (lower == "pgdown" || lower == "next") then
              "Next"
            else if lower == "backspace" then
              "BackSpace"
            else if lower == "tab" then
              "Tab"
            else
              part;
        in
        lib.concatStringsSep "+" (map canon parts);

      normalizeMap =
        m:
        let
          pairs = lib.mapAttrsToList (k: v: {
            key = normalizeKey k;
            val = v;
            orig = k;
          }) m;
          names = map (p: p.key) pairs;
          uniq = lib.unique names;
        in
        if (lib.length uniq) != (lib.length names) then
          throw (
            "Duplicate i3 keybindings after normalization: " + (lib.concatMapStringsSep ", " (p: p.orig) pairs)
          )
        else
          lib.listToAttrs (map (p: lib.nameValuePair p.key p.val) pairs);
    in
    {
      inherit normalizeKey normalizeMap;
      # Document the canonical style we enforce
      style = {
        modifiers = [
          "Ctrl"
          "Shift"
          "Alt"
          "super"
        ];
        special = {
          enter = "Return";
          escape = "Escape";
          pageUp = "Prior";
          pageDown = "Next";
          backspace = "BackSpace";
        };
        separator = "+";
      };
    };
}
