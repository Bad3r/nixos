_: {
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        codex
        github-mcp-server
      ];
    };
}
