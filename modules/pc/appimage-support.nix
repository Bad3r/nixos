_: {
  flake.modules.nixos.pc = _: {
    # Enable AppImage support with binfmt registration
    # This allows AppImages to run directly like native executables
    programs.appimage = {
      enable = true;
      binfmt = true; # Register AppImages with kernel binfmt_misc
    };

    # Optional: Add extra libraries if some AppImages fail
    # Uncomment and add missing libraries as needed:
    # programs.appimage.package = pkgs.appimage-run.override {
    #   extraPkgs = pkgs: [
    #     pkgs.libthai     # For some media apps
    #     pkgs.libsecret   # For apps needing keyring access
    #     # Add other missing libraries here
    #   ];
    # };
  };
}
