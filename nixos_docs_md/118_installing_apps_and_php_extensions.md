## Installing Apps and PHP extensions

Nextcloud apps are installed statefully through the web interface. Some apps may require extra PHP extensions to be installed. This can be configured with the [`services.nextcloud.phpExtraExtensions`](options.html#opt-services.nextcloud.phpExtraExtensions) setting.

Alternatively, extra apps can also be declared with the [`services.nextcloud.extraApps`](options.html#opt-services.nextcloud.extraApps) setting. When using this setting, apps can no longer be managed statefully because this can lead to Nextcloud updating apps that are managed by Nix:

```programlisting
{ config, pkgs, ... }:
{
  services.nextcloud.extraApps = with config.services.nextcloud.package.packages.apps; {
    inherit user_oidc calendar contacts;
  };
}
```

Keep in mind that this is essentially a mirror of the apps from the appstore, but managed in nixpkgs. This is by no means a curated list of apps that receive special testing on each update.

If you want automatic updates it is recommended that you use web interface to install apps.
