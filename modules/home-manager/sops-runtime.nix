_: {
  flake.homeManagerModules.sopsRuntime =
    {
      inputs,
      lib,
      metaOwner,
      ...
    }:
    let
      homeDirectory = "/home/${metaOwner.username}";
      sopsServiceHome = "${homeDirectory}/.local/share/sops-nix";
    in
    {
      imports = [ inputs.sops-nix.homeManagerModules.sops ];

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
