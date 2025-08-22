## Building Mattermost plugins

The `mattermost` derivation includes the `buildPlugin` passthru for building plugins that use the “standard” Mattermost plugin build template at [mattermost-plugin-demo](https://github.com/mattermost/mattermost-plugin-demo).

Since this is a “de facto” standard for building Mattermost plugins that makes assumptions about the build environment, the `buildPlugin` helper tries to fit these assumptions the best it can.

Here is how to build the above Todo plugin. Note that we rely on package-lock.json being assembled correctly, so must use a version where it is! If there is no lockfile or the lockfile is incorrect, Nix cannot fetch NPM build and runtime dependencies for a sandbox build.

```programlisting
{
  services.mattermost = {
    plugins = with pkgs; [
      (mattermost.buildPlugin {
        pname = "mattermost-plugin-todo";
        version = "0.8-pre";
        src = fetchFromGitHub {
          owner = "mattermost-community";
          repo = "mattermost-plugin-todo";
          # 0.7.1 didn't work, seems to use an older set of node dependencies.

          rev = "f25dc91ea401c9f0dcd4abcebaff10eb8b9836e5";
          hash = "sha256-OM+m4rTqVtolvL5tUE8RKfclqzoe0Y38jLU60Pz7+HI=";
        };
        vendorHash = "sha256-5KpechSp3z/Nq713PXYruyNxveo6CwrCSKf2JaErbgg=";
        npmDepsHash = "sha256-o2UOEkwb8Vx2lDWayNYgng0GXvmS6lp/ExfOq3peyMY=";
        extraGoModuleAttrs = {
          npmFlags = [ "--legacy-peer-deps" ];
        };
      })
    ];
  };
}
```

See `pkgs/by-name/ma/mattermost/build-plugin.nix` for all the options. As in the previous example, once the plugin is installed and the config rebuilt, you can enable this plugin in the System Console.
