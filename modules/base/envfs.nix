_: {
  flake.nixosModules.base = {
    services.envfs.enable = true;

    # Make envfs resolve entries for stat/readdir-style probes so FHS compatibility
    # works for tools that inspect /bin and /usr/bin instead of only execing paths.
    environment.variables.ENVFS_RESOLVE_ALWAYS = "1";
  };
}
