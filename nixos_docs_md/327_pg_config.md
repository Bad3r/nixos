## `pg_config`

`pg_config` is not part of the `postgresql`-package itself. It is available under `postgresql_<major>.pg_config` and `libpq.pg_config`. Use the `pg_config` from the postgresql package you’re using in your build.

Also, `pg_config` is a shell-script that replicates the behavior of the upstream `pg_config` and ensures at build-time that the output doesn’t change.

This approach is done for the following reasons:

- By using a shell script, cross compilation of extensions is made easier.

- The separation allowed a massive reduction of the runtime closure’s size. Any attempts to move `pg_config` into `$dev` resulted in brittle and more complex solutions (see commits [`0c47767`](https://github.com/NixOS/nixpkgs/commit/0c477676412564bd2d5dadc37cf245fe4259f4d9), [`435f51c`](https://github.com/NixOS/nixpkgs/commit/435f51c37faf74375134dfbd7c5a4560da2a9ea7)).

- `pg_config` is only needed to build extensions or in some exceptions for building client libraries linking to `libpq.so`. If such a build works without `pg_config`, this is strictly preferable over adding `pg_config` to the build environment.

  With the current approach it’s now explicit that this is needed.
