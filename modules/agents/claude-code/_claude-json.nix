# ~/.claude.json keys; mcpServers comes from modules/agents/mcp/servers.nix.
# Every key set here replaces Claude's copy on each switch; commenting it out
# again removes it.
{
  hasTrustDialogAccepted = true;
  hasCompletedProjectOnboarding = true;
  bypassPermissionsModeAccepted = true;
  autoCompactEnabled = true;
  autoConnectIde = false;
  autoUpdates = false;
  claudeInChromeDefaultEnabled = true;
  defaultToAgentsView = true;
  diffTool = "diff";
  editorMode = "vim";
  externalEditorContext = true;
  preferredNotifChannel = "iterm2_with_bell";
  theme = "dark";
  verbose = true;
}
