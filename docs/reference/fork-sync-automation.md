# Fork Sync Automation

Each flake-input fork carries a scheduled GitHub workflow,
`.github/workflows/sync-upstream.yml`, that merges the same-named upstream
branch into the fork branch every 8 hours. `git-fork-sync` from
`modules/apps/git-fork-utils.nix` remains the one-command manual sync and the
conflict-recovery path.

## Covered Forks

| Fork                   | Branch             | Upstream                     | Local clone                               |
| ---------------------- | ------------------ | ---------------------------- | ----------------------------------------- |
| `Bad3r/nixpkgs`        | `nixpkgs-unstable` | `NixOS/nixpkgs`              | `/data/Projects/igit/fork-nixpkgs`        |
| `Bad3r/home-manager`   | `master`           | `nix-community/home-manager` | `/data/Projects/igit/fork-home-manager`   |
| `Bad3r/stylix`         | `master`           | `nix-community/stylix`       | `/data/Projects/igit/fork-stylix`         |
| `Bad3r/llm-agents.nix` | `main`             | `numtide/llm-agents.nix`     | `/data/Projects/igit/llm-agents.nix-fork` |

## Behavior

- Schedule: `17 */8 * * *` (every 8 hours), plus `workflow_dispatch` for
  manual runs.
- The job calls `POST /repos/{owner}/{repo}/merge-upstream`, the API behind
  the GitHub "Sync fork" button. No checkout happens, so scheduled runs stay
  cheap even for nixpkgs.
- Outcomes: `none` when the fork is not behind upstream (no empty commits),
  `fast-forward` when the fork carries no local commits, `merge` when the
  histories diverged and merge cleanly.
- A merge conflict fails the API call with HTTP 409, the run fails, and
  GitHub sends the standard workflow-failure notification. The workflow never
  force-pushes and never rewrites fork history.
- The run step summary records the merge type, the upstream message, and the
  branch head SHA before and after the sync.

## Requirements

- The workflow file must live on the fork default branch; scheduled workflows
  fire only from the default branch. Every covered fork uses its flake branch
  as the default branch.
- GitHub Actions must be enabled on the fork repository.
- GitHub disables scheduled workflows in public repositories after 60 days
  without repository activity. If GitHub sends such a notice, re-enable with
  `gh workflow enable sync-upstream.yml -R <owner>/<repo>`.

## Manual Operations

Dispatch and watch a sync run:

```sh
gh workflow run sync-upstream.yml -R Bad3r/nixpkgs --ref nixpkgs-unstable
gh run list --workflow=sync-upstream.yml -R Bad3r/nixpkgs --limit 1
```

Sync a local clone, which is also the conflict-recovery path (resolve the
merge locally, then push):

```sh
git-fork-sync -c /data/Projects/igit/fork-nixpkgs
```

## Adding A Fork

Run the installer against a local clone checked out on the fork default
branch:

```sh
scripts/install-fork-sync-workflow.sh /data/Projects/igit/<clone>
```

The installer writes the canonical workflow, commits and pushes it, enables
GitHub Actions when disabled, and dispatches a verification run. The
canonical workflow content lives in the installer heredoc; keep changes to
the workflow and the installer in one commit.
