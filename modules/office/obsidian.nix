{
  nixpkgs.allowedUnfreePackages = [
    "obsidian"
  ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        obsidian
      ];
    };
}
