## Forgejo

**Table of Contents**

[Migration from Gitea](#module-forgejo-migration-gitea)

Forgejo is a soft-fork of gitea, with strong community focus, as well as on self-hosting and federation. [Codeberg](https://codeberg.org) is deployed from it.

See [upstream docs](https://forgejo.org/docs/latest/).

The method of choice for running forgejo is using [`services.forgejo`](options.html#opt-services.forgejo.enable).

### Warning

Running forgejo using `services.gitea.package = pkgs.forgejo` is no longer recommended. If you experience issues with your instance using `services.gitea`, **DO NOT** report them to the `services.gitea` module maintainers. **DO** report them to the `services.forgejo` module maintainers instead.
