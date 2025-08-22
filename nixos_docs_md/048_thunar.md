## Thunar

Thunar (the Xfce file manager) is automatically enabled when Xfce is enabled. To enable Thunar without enabling Xfce, use the configuration option [`programs.thunar.enable`](options.html#opt-programs.thunar.enable) instead of adding `pkgs.xfce.thunar` to [`environment.systemPackages`](options.html#opt-environment.systemPackages).

If you’d like to add extra plugins to Thunar, add them to [`programs.thunar.plugins`](options.html#opt-programs.thunar.plugins). You shouldn’t just add them to [`environment.systemPackages`](options.html#opt-environment.systemPackages).
