## Maintainer information

As stated in the previous paragraph, we must provide a clean upgrade-path for Nextcloud since it cannot move more than one major version forward on a single upgrade. This chapter adds some notes how Nextcloud updates should be rolled out in the future.

While minor and patch-level updates are no problem and can be done directly in the package-expression (and should be backported to supported stable branches after that), major-releases should be added in a new attribute (e.g. Nextcloud `v19.0.0` should be available in `nixpkgs` as `pkgs.nextcloud19`). To provide simple upgrade paths it’s generally useful to backport those as well to stable branches. As long as the package-default isn’t altered, this won’t break existing setups. After that, the versioning-warning in the `nextcloud`-module should be updated to make sure that the [package](options.html#opt-services.nextcloud.package)-option selects the latest version on fresh setups.

If major-releases will be abandoned by upstream, we should check first if those are needed in NixOS for a safe upgrade-path before removing those. In that case we should keep those packages, but mark them as insecure in an expression like this (in `<nixpkgs/pkgs/servers/nextcloud/default.nix>`):

```programlisting

# ...;
}
```

Ideally we should make sure that it’s possible to jump two NixOS versions forward: i.e. the warnings and the logic in the module should guard a user to upgrade from a Nextcloud on e.g. 19.09 to a Nextcloud on 20.09.
