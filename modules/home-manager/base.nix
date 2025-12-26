_: {
  flake.homeManagerModules.base =
    {
      lib,
      metaOwner,
      ...
    }:
    let
      # Construct homeDirectory from metaOwner directly, don't rely on config.home.homeDirectory
      homeDirectory = "/home/${metaOwner.username}";
      sopsServiceHome = "${homeDirectory}/.local/share/sops-nix";
    in
    {
      # Don't set home.username/homeDirectory - they're set explicitly in nixos.nix
      home.preferXdgDirectories = true;

      programs.home-manager.enable = true;
      systemd.user.startServices = "sd-switch";

      # Use homeDirectory from metaOwner, not config.home.homeDirectory
      sops.age.keyFile = lib.mkDefault "${homeDirectory}/.config/sops/age/keys.txt";

      home.activation.ensureSopsServiceHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p '${sopsServiceHome}'
        chmod 700 '${sopsServiceHome}'
      '';

      systemd.user.services.sops-nix.Service.Environment = lib.mkForce [
        "HOME=${sopsServiceHome}"
      ];
    };
}
