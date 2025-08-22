## Wingpanel and Switchboard plugins

Wingpanel and Switchboard work differently than they do in other distributions, as far as using plugins. You cannot install a plugin globally (like with `environment.systemPackages`) to start using it. You should instead be using the following options:

- [`services.xserver.desktopManager.pantheon.extraWingpanelIndicators`](options.html#opt-services.xserver.desktopManager.pantheon.extraWingpanelIndicators)

- [`services.xserver.desktopManager.pantheon.extraSwitchboardPlugs`](options.html#opt-services.xserver.desktopManager.pantheon.extraSwitchboardPlugs)

to configure the programs with plugs or indicators.

The difference in NixOS is both these programs are patched to load plugins from a directory that is the value of an environment variable. All of which is controlled in Nix. If you need to configure the particular packages manually you can override the packages like:

```programlisting
wingpanel-with-indicators.override {
  indicators = [ pkgs.some-special-indicator ];
}
```

```programlisting
switchboard-with-plugs.override { plugs = [ pkgs.some-special-plug ]; }
```

please note that, like how the NixOS options describe these as extra plugins, this would only add to the default plugins included with the programs. If for some reason you’d like to configure which plugins to use exactly, both packages have an argument for this:

```programlisting
wingpanel-with-indicators.override {
  useDefaultIndicators = false;
  indicators = specialListOfIndicators;
}
```

```programlisting
switchboard-with-plugs.override {
  useDefaultPlugs = false;
  plugs = specialListOfPlugs;
}
```

this could be most useful for testing a particular plug-in in isolation.
