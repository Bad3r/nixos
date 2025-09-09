_: {
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        codex
        github-mcp-server
      ];
    };
}
