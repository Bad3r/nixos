# UI preferences for ~/.claude.json. Merged with the existing file and with
# mcpServers (from modules/agents/mcp/servers.nix) by the settings producer.
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
