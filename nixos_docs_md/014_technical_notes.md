## Technical Notes

The config value enforcement is implemented via `mkImageMediaOverride = mkOverride 60;` and therefore primes over simple value assignments, but also yields to `mkForce`.

This property allows image designers to implement in semantically correct ways those configuration values upon which the correct functioning of the image depends.

For example, the iso base image overrides those file systems which it needs at a minimum for correct functioning, while the installer base image overrides the entire file system layout because there can’t be any other guarantees on a live medium than those given by the live medium itself. The latter is especially true before formatting the target block device(s). On the other hand, the netboot iso only overrides its minimum dependencies since netboot images are always made-to-target.
