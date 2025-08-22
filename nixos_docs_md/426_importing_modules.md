## Importing Modules

Sometimes NixOS modules need to be used in configuration but exist outside of Nixpkgs. These modules can be imported:

```programlisting
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Use a locally-available module definition in

    # ./example-module/default.nix

    ./example-module
  ];

  services.exampleModule.enable = true;
}
```
