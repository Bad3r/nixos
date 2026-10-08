# ~/.claude.json keys; mcpServers comes from modules/agents/mcp/servers.nix.
# Every key set here replaces Claude's copy on each switch; commenting it out
# again removes it.
{
  autoConnectIde = false;
  autoUpdates = false;
  bypassPermissionsModeAccepted = true;
  claudeInChromeDefaultEnabled = true;
  defaultToAgentsView = true;
  diffTool = "diff";
  externalEditorContext = true;
}
