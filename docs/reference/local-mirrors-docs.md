# Local mirror docs

Two services publish documentation trees from mirrors after each successful [sync](local-mirrors-sync.md), each switched on under its own `programs.gitMirror` option.
A tree lands beside its source mirror in a directory with a `-docs` suffix, and `current` in it is a symlink to the newest build.
Each service holds the same lock as the sync job of its mirror, so a build never reads a checkout mid-sync.
Each keeps the newest `maxRevisions` builds and exits early when `current` already matches the source.

Run a service and read its log, as the owner:

```sh
systemctl --user start git-mirror-firefox-docs.service
journalctl --user -u git-mirror-firefox-docs.service -n 100 --no-pager
```

The Python publisher runs the same way as `git-mirror-python-docs.service`.

## Firefox source docs

`git-mirror-firefox-docs.service` runs `./mach doc` in the Firefox mirror, configured under `programs.gitMirror.firefoxDocs`.
The output stays outside the checkout, so the sync can keep the source tree clean.

| Path in `mozilla-firefox-firefox-docs` | Content                       |
| -------------------------------------- | ----------------------------- |
| `current`                              | Newest build                  |
| `revisions/<sha>/<format>`             | Build of one source revision  |
| `last-built-revision`                  | Revision and options of build |
| `state`, `cache`                       | `mach` state and caches       |

A change to the `mach doc` options rebuilds the current revision, since `last-built-revision` records them.
The service skips a mirror without a checkout, an executable `mach`, or a valid `HEAD`.
It fails on a checkout with local changes; a build that dirties the checkout only logs a warning, since the next sync cleans it.
With `linkcheck` set, a second `mach doc --linkcheck` pass writes to `linkcheck/<sha>`, pruned like the builds.

## Python documentation sources

`git-mirror-python-docs.service` publishes the `Doc/` tree of the current stable CPython branch, configured under `programs.gitMirror.pythonDocs`.
CPython `main` tracks the next release, so the service reads the stable minor version from the title of the `versionUrl` page.
It archives `Doc/` from `origin/<major.minor>`, fetching that branch when the mirror lacks it.
When the Python project promotes a new stable version, the next run moves `current` to its branch.

| Path in `python-cpython-docs`  | Content                         |
| ------------------------------ | ------------------------------- |
| `current`                      | Newest `Doc/` tree              |
| `revisions/<branch>-<sha>/Doc` | Tree of one branch and commit   |
| `current-branch`               | Branch, commit, and version URL |

A tree without `conf.py`, `contents.rst`, and `library/` is never published.
An incomplete revision directory is deleted and extracted again.
