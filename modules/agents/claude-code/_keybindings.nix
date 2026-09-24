# ~/.claude/keybindings.json data. Claude only reads this file, so Home
# Manager owns it outright instead of jq-merging like settings.json.
#
# alt+t is upstream meta+t, canonicalized on Linux. The toggle turns thinking
# off for the session, and the API then rejects effort `max`. /config keeps a
# deliberate path to the same setting.
{
  "$schema" = "https://www.schemastore.org/claude-code-keybindings.json";
  "$docs" = "https://code.claude.com/docs/en/keybindings";
  bindings = [
    {
      context = "Chat";
      bindings."alt+t" = null;
    }
  ];
}
