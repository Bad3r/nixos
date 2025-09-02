{ config, ... }:
{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        github-mcp-server
      ];
    };
}
