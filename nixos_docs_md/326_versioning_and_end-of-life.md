## Versioning and End-of-Life

PostgreSQL’s versioning policy is described [here](https://www.postgresql.org/support/versioning/). TLDR:

- Each major version is supported for 5 years.

- Every three months there will be a new minor release, containing bug and security fixes.

- For criticial/security fixes there could be more minor releases inbetween. This happens _very_ infrequently.

- After five years, a final minor version is released. This usually happens in early November.

- After that a version is considered end-of-life (EOL).

- Around February each year is the first time an EOL-release will not have received regular updates anymore.

Technically, we’d not want to have EOL’ed packages in a stable NixOS release, which is to be supported until one month after the previous release. Thus, with NixOS’ release schedule in May and November, the oldest PostgreSQL version in nixpkgs would have to be supported until December. It could be argued that a soon-to-be-EOL-ed version should thus be removed in May for the .05 release already. But since new security vulnerabilities are first disclosed in February of the following year, we agreed on keeping the oldest PostgreSQL major version around one more cycle in [\#310580](https://github.com/NixOS/nixpkgs/pull/310580#discussion_r1597284693).

Thus, our release workflow is as follows:

- In May, `nixpkgs` packages the beta release for an upcoming major version. This is packaged for nixos-unstable only and will not be part of any stable NixOS release.

- In September/October the new major version will be released, replacing the beta package in nixos-unstable.

- In November the last minor version for the oldest major will be released.

- Both the current stable .05 release and nixos-unstable should be updated to the latest minor that will usually be released in November.
  - This is relevant for people who need to use this major for as long as possible. In that case its desirable to be able to pin nixpkgs to a commit that still has it, at the latest minor available.

- In November, before branch-off for the .11 release and after the update to the latest minor, the EOL-ed major will be removed from nixos-unstable.

This leaves a small gap of a couple of weeks after the latest minor release and the end of our support window for the .05 release, in which there could be an emergency release to other major versions of PostgreSQL - but not the oldest major we have in that branch. In that case: If we can’t trivially patch the issue, we will mark the package/version as insecure **immediately**.
