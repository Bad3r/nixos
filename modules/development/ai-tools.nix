_: {
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = with pkgs; [
        claude-code
        codex
        github-mcp-server
      ];
    };
}
