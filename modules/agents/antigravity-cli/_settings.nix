# ~/.gemini/antigravity-cli/settings.json keys that permissions do not hold.
# Every key set here replaces the CLI's copy on each switch; commenting it out
# again removes it. Model and trustedWorkspaces remain unset so runtime choices
# persist.
{
  "$schema" = "https://antigravity.google/schemas/v1/settings.json";

  # Startup execution mode: "" | "accept-edits" | "auto" | "plan"
  agentMode = "auto";

  # Allow read/write checks outside active workspace roots (gated by permissions)
  allowNonWorkspaceAccess = true;

  # Screen buffer mode: "default" | "always" | "never"
  altScreenMode = "always";

  # Artifact review policy: "asks-for-review" | "agent-decides" | "always-proceed"
  # artifactReviewPolicy = "asks-for-review";

  # Preserve terminal scrollback across window resizes in inline mode
  # clearScrollbackOnResize = true;

  # Visual theme: "terminal" | "light" | "solarized light" | "colorblind-friendly light" | "dark" | "solarized dark" | "colorblind-friendly dark" | "tokyo night"
  # colorScheme = "terminal";

  # Copy selection on mouse release in alt-screen mode
  copyOnSelect = true;

  # Disable /slash-command expansion in headless (-p) mode
  # disableSlashCommands = false;

  # External editor for Ctrl+G and artifacts ("auto" uses $EDITOR)
  # editor = "auto";

  # Prompt input editing mode: "default" | "vim"
  editorMode = "vim";

  # Isolate terminal commands in OS namespaces
  enableTerminalSandbox = true;

  # Hide active subagents and background tasks below the prompt box
  # hideActiveItems = false;

  # Prompt history entries retained on disk (-1 unlimited)
  # historySize = 2000;

  # Desktop notifications and terminal bell on approvals or turn completion
  notifications = true;

  # Models for Orchestrator mode roles, named as the model picker lists them
  orchestrator = {
    planner = "Gemini 4 Neon (High)";
    executor = "Gemini 4 Hydrogen (High)";
  };

  # /resume picker grouping: "none" | "grouped"
  # pickerGrouping = "none";

  # Message submission while agent works: "queue" | "send-immediately"
  # queuedMessages = "queue";

  # Progress animation speed: "fast" | "medium" | "slow" | "off"
  # runningLightSpeed = "medium";

  # Periodic feedback surveys after completions
  showFeedbackSurvey = false;

  # Usage tips while generating responses
  # showTips = true;

  # Tool approval fallback: "request-review" | "proceed-in-sandbox" | "always-proceed" | "strict"
  toolPermission = "proceed-in-sandbox";

  # Use Google AI credits when plan quota runs out
  # useG1Credits = false;

  # Keep terminal's native cursor shape instead of a block cursor
  # useTerminalCursor = false;

  # Visual verbosity: "high" | "medium" | "low"
  verbosity = "high";

  # Start vim prompt in Insert mode where bare Enter submits
  # vimInsertFirst = false;
}
