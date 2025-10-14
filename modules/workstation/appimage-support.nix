_: {
  flake.nixosModules.roles.system.base.imports = [
    (_: {
      programs.appimage = {
        enable = true;
        binfmt = true;
      };
    })
  ];
}
