_: {
  configurations.nixos.tec.module =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Development tools
        kiro-fhs # Kiro editor with FHS environment
        vscode-fhs # VS Code with FHS environment
      ];
    };
}
