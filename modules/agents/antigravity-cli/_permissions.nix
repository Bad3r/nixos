# Fine-grained allow, ask, and deny rules shared between
# ~/.gemini/antigravity-cli/settings.json (`permissions`) and
# ~/.gemini/config/config.json (`userSettings.globalPermissionGrants`).
#
# Rules evaluate deny > ask > allow as `action(target)` strings. Under
# `agentMode = "auto"` and `enableTerminalSandbox = true`, sandboxed commands run
# without prompting while allowed `read_file`, `write_file`, and `read_url`
# targets populate sandbox mounts and outbound domains; `command(...)` allow
# rules also permit those prefixes outside the sandbox without prompting, so keep
# interpreters, shells, and file writers off `commandAllow`.
{
  homeDir,
  scratchDir,
  sbx,
  mcpAutoApproved,
}:
let
  command = cmd: "command(${cmd})";

  # Host/daemon CLI tools that require access outside the terminal sandbox
  # (nix-daemon socket, libvirt, git/worktrees, GitHub API, OCR delegation).
  # General utilities, shells, and interpreters auto-run inside the sandbox
  # under `auto` + `proceed-in-sandbox` without granting host-wide escapes.
  commandAllow = [
    "gh"
    "git"
    "nix"
    "ocr delegate"
  ]
  ++ (if sbx then [ "sbx" ] else [ ]);

  # High-impact commands that prompt even when a broader prefix is allowed;
  # gates `bash -c`/`-lc` and `zsh -c`/`-lc` while leaving bare shells off
  # `commandAllow` so flag variants cannot run unsandboxed without prompting.
  commandAsk = [
    "gh repo delete"
    "gh pr close --delete-branch"
    "bash -c"
    "bash -lc"
    "zsh -c"
    "zsh -lc"
  ]
  ++ (
    if sbx then
      [
        "sbx base prepare"
        "sbx --json base prepare"
      ]
    else
      [ ]
  );

  # Absolute coreutils `rm` paths bypass the PATH trash shim and delete
  # files permanently; also explicitly deny SOPS age identity reads even if
  # adjacent directories are accessed outside the sandbox.
  commandDeny = [
    "/bin/rm"
    "/usr/bin/rm"
    "/run/current-system/sw/bin/rm"
  ];

  fileDeny = [
    "read_file(${homeDir}/.config/sops)"
  ];

  # Extra read-only/read-write mounts and outbound domains layered onto the
  # active workspace and terminal sandbox. Keep `~/.gemini/config` read-only so
  # declarative hooks, MCP servers, and settings cannot be edited silently, and
  # avoid exposing `~/.config` (which contains SOPS age keys) or `~/.gemini` root.
  fileWebAllow = [
    "read_file(/nix/store)"
    "read_file(/run/current-system)"
    "read_file(${homeDir}/.gemini/config)"
    "read_file(${homeDir}/nixos)"
    "write_file(${scratchDir})"
    "write_file(${homeDir}/.gemini/antigravity/brain)"
    "write_file(${homeDir}/.gemini/antigravity-cli/brain)"
    "read_url(antigravity.google)"
    "read_url(github.com)"
  ];
in
{
  allow = fileWebAllow ++ map command commandAllow ++ map (name: "mcp(${name}/*)") mcpAutoApproved;
  ask = map command commandAsk;
  deny = fileDeny ++ map command commandDeny;
}
