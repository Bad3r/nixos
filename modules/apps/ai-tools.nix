{
  flake.nixosModules.apps."ai-tools" =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        codex
        github-mcp-server
      ];
    };

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
