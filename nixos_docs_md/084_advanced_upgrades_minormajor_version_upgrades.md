## Advanced upgrades (minor/major version upgrades)

Here are some baseline instructions to handle advanced upgrades in Garage, when in doubt, please refer to upstream instructions.

- Disable API and web access to Garage.

- Perform `garage-manage repair --all-nodes --yes tables` and `garage-manage repair --all-nodes --yes blocks`.

- Verify the resulting logs and check that data is synced properly between all nodes. If you have time, do additional checks (`scrub`, `block_refs`, etc.).

- Check if queues are empty by `garage-manage stats` or through monitoring tools.

- Run `systemctl stop garage` to stop the actual Garage version.

- Backup the metadata folder of ALL your nodes, e.g. for a metadata directory (the default one) in `/var/lib/garage/meta`, you can run `pushd /var/lib/garage; tar -acf meta-v0.7.tar.zst meta/; popd`.

- Run the offline migration: `nix-shell -p garage_1 --run "garage offline-repair --yes"`, this can take some time depending on how many objects are stored in your cluster.

- Bump Garage version in your NixOS configuration, either by changing [stateVersion](options.html#opt-system.stateVersion) or bumping [services.garage.package](options.html#opt-services.garage.package), this should restart Garage automatically.

- Perform `garage-manage repair --all-nodes --yes tables` and `garage-manage repair --all-nodes --yes blocks`.

- Wait for a full table sync to run.

Your upgraded cluster should be in a working state, re-enable API and web access.
