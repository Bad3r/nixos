_:
let
  commitSelectModeSection = command: ''
    ## Select Mode

    Use `worktree_atomic` for new work, `existing_task` to continue an authorized task on its existing non-main branch, and `direct_current_branch` for explicitly requested current-branch execution, including `main` or `master`.

    For new work:

    1. `${command}` means commit only (no push, no PR) in a newly created worktree.
    2. `${command} and push` means commit + push + PR + labels from a newly created worktree, unless the user explicitly requests the current branch.
    3. `${command} ... create pull request` means commit + push + PR + labels from a newly created worktree.
    4. `${command} ... explicit branch` uses the provided text as the branch seed, then still creates a brand-new unique branch.

    For an existing task or PR, reuse its verified branch and worktree instead of creating another branch or PR. Retain the publication scope already authorized in the conversation; a commit-only request does not authorize a push.
  '';

  commitSkillBody = ''
    If the user provides an explicit commit message argument, use it after checks. Resolve routine choices from the task and prior authorization; ask only when missing information materially affects scope or risks unrelated work.
    Committing on `main` or `master` requires explicit current-branch authorization. Reuse a non-main task branch only when its identity and authorization are established.
    Continuing an authorized task on its existing non-main branch does not require renewed branch or publication approval. Honor explicit holds until the user supersedes them.
    In `existing_task` mode, verify branch ownership, the PR head when present, and unrelated work before editing. For new tasks, create a fresh branch and worktree.

    Task authorization does not extend to other repositories, consumer lock bumps, merging, or activation. Perform those actions only when they are within the authorized scope.

    ## Apply `~/trees` Naming Standard

    Use this structure for all new worktrees:

    ```bash
    repo_name="$(basename "$(git rev-parse --show-toplevel)")"
    trees_repo_dir="$HOME/trees/$repo_name"
    ```

    Always create worktrees under `"$trees_repo_dir"` and never directly under `~/trees` root.

    Infer naming from existing directory names in `"$trees_repo_dir"`:

    - If names follow `type-slug` (for example `feat-user-defaults`, `fix-mcp-json-schema`, `docs-documentation-audit`), use:
      - Branch name: `type/slug`
      - Worktree directory: `type-slug` (branch name with `/` replaced by `-`)
    - If names follow non-type phase/task style (for example `phase-7-5-deploy-verification`), use the same hyphenated value for both branch and worktree directory.
    - If no entries exist, default to `type/slug` branch naming and `type-slug` worktree directories.

    For new work, treat a provided branch name as a seed and generate a unique branch from it.
    For an existing task, resolve its branch from the conversation and current PR metadata; matching changed filenames alone do not establish task identity.

    ## Enforce Non-Negotiable Safety Rules

    Apply these rules in every mode unless the user explicitly authorizes the specific exception:

    - Never run `git stash drop` or `git stash clear`.
    - Never run `git reset --hard` unless the user explicitly requests it.
    - Never run `git clean -fd`.
    - Never run `git add -A` or `git add .`; stage explicit file paths only.
    - Never run `git push --force` to `main` or `master`.
    - Treat `flake.lock` as protected and exclude it from transfer, staging, and cleanup unless updating it is explicitly within the authorized task.
    - When moving edits to a new worktree with explicit file paths, only those paths must become clean in the invoking checkout before staging or commit continues.
    - If the required cleanup scope remains dirty after transfer, fail hard and report remaining paths.

    After a pre-commit hook failure, never run `git commit --amend` unless the user explicitly asks to amend the previous commit.

    ## Enforce Main Branch Protection (Default Mode)

    Apply this guard before any staging or commit unless `current_branch_explicit=true`:

    - Never run `git commit` when current branch is `main` or `master`.
    - Never perform commit operations in-place on the primary checkout when it is on `main` or `master`.
    - For new tasks, create a new worktree and non-main branch. An existing authorized task may reuse its verified non-main branch.
    - Exception: if the user explicitly requests current-branch execution, allow in-place commit/push on the active branch, including `main` or `master`.

    ## Require Invocation-Local Worktree Creation

    Enforce this gate before any `git add` or `git commit` in `worktree_atomic` mode:

    1. Snapshot existing worktree paths at invocation start:

    ```bash
    git worktree list --porcelain
    ```

    2. Create a brand-new worktree path under `~/trees/repo-name` that did not exist at invocation start.
    3. Re-read `git worktree list --porcelain` and verify the new path appears in the post-create list and was absent in the pre-create list.
    4. Refuse execution if verification fails, or if the selected path existed before invocation.
    5. Refuse execution if the command flow attempts to stage or commit before this verification passes.

    ## Require Invocation-Local Branch Creation

    Enforce this gate before any `git worktree add`, `git add`, or `git commit` in `worktree_atomic` mode:

    1. Snapshot existing local and remote branch names at invocation start:

    ```bash
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes
    ```

    2. Build `new_branch` from branch seed using established style.
    3. Verify `new_branch` does not exist in pre-snapshot local or remote refs.
    4. If it exists, append deterministic suffix (`-r2`, `-r3`, ...) until unique.
    5. Refuse execution if flow attempts to create or use a branch name that existed before invocation.

    ## Run Preflight Checks

    Run these checks before staging and committing:

    ```bash
    git status --short
    git diff --staged --stat
    git diff --stat
    git log --oneline -5
    ```

    ## Stage Changes Intentionally

    Use atomic staging rules:

    - Stage only files for one logical concern.
    - Use explicit paths: `git add path/to/file1 path/to/file2`.
    - Exclude `flake.lock` from staging unless updating it is explicitly within the authorized task.
    - Split unrelated concerns into separate commits.

    If nothing is staged, inspect unstaged changes and stage the explicit paths belonging to the authorized task. Preserve unrelated changes. Ask only when ownership or scope cannot be determined safely.

    ## Write Commit Messages

    Use Conventional Commits format: `type(scope): summary`.

    Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`.

    Choose scope from the primary module/directory/domain affected. Keep summary concise and focused on intent.

    Use a heredoc for multi-line messages:

    ```bash
    git commit -m "$(cat <<'MSG'
    type(scope): summary

    Optional body with context.
    MSG
    )"
    ```

    ## Execute Workflow

    1. Parse intent flags from the user request:
       - `push_required` for push requests
       - `pr_required` for PR requests
       - `labels_required` when PR labels are requested
       - `current_branch_explicit` only when the user clearly requests current-branch execution
       - `existing_task` when continuing an authorized task on its verified existing non-main branch
       - `reuse_existing_branch` when `current_branch_explicit` or `existing_task` is true
       - `requested_paths` from explicit file names or the verified scope of the authorized task
       - `keep_source_paths` when the user explicitly asks to keep source-checkout edits
       - `flake_lock_explicit` when updating `flake.lock` is explicitly within the authorized task
    2. Normalize intent flags:
       - Retain commit, push, and PR authorization from earlier turns of the same task, subject to later scope restrictions.
       - If `reuse_existing_branch` is false and `push_required` is true, set `pr_required=true` and `labels_required=true`.
       - If `reuse_existing_branch` is false and `pr_required` is true, set `labels_required=true`.
       - For an existing PR, update that PR; do not create another PR. For direct current-branch execution, do not add PR operations outside the authorized scope.
       - If `flake_lock_explicit` is false, remove `flake.lock` from `requested_paths`.
       - If `requested_paths` becomes empty after filtering, report that no authorized changes remain; ask only if unresolved scope prevents completing the task.
       - Set `cleanup_source_paths=true` when `requested_paths` is non-empty and `keep_source_paths` is false.
    3. If `reuse_existing_branch` is true, use the verified task worktree and skip steps 4-16. Main/master still requires explicit current-branch authorization.
    4. Resolve branch seed in this order:
       - Explicit branch text from user input
       - Explicit ticket/issue id from user input
       - New seed inferred from request slug + established naming style
    5. Select base branch in this order:
       - User-specified base
       - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
       - Fallback `main`, then `master` if present
    6. Compute `repo_name` and `trees_repo_dir`, then ensure `"$trees_repo_dir"` exists.
    7. Capture pre-create worktree list.
    8. Capture pre-create branch list (local + remote refs).
    9. Infer naming style from `~/trees/<repo_name>` and build provisional branch/worktree names from branch seed.
    10. Enforce invocation-local branch creation gate by suffixing until branch name is globally unique against pre-snapshot refs.
    11. Derive `new_worktree_name` from final `new_branch` by replacing `/` with `-`.
    12. Ensure `new_branch` is never `main` or `master`.
    13. If `"$HOME/trees/$repo_name/$new_worktree_name"` already exists, append a deterministic suffix (`-r2`, `-r3`, ...) until unique.
    14. Create worktree and new branch from base:

    ```bash
    git worktree add -b new-branch "$HOME/trees/$repo_name/new-worktree-name" base-branch
    ```

    15. Capture post-create worktree list and verify invocation-local creation gate passed.
    16. Move pending edits out of the invoking checkout into the new worktree before switching active directory:
       - Record `invoking_checkout="$(pwd)"` before changing directories; use this for source-scope cleanup and verification commands.
       - Resolve transfer scope:
         - If `requested_paths` is non-empty, transfer only those paths.
         - Otherwise transfer all pending paths except `flake.lock` by default.
       - Detect pending state inside the transfer scope.
       - If no pending edits exist in scope, skip transfer and continue.
       - Create a uniquely tagged transfer stash for the scoped paths:

    ```bash
    git stash push --include-untracked --message "commit-skill-transfer-<nonce>" -- <scoped-paths...>
    ```

       - For full-scope transfers, use scoped paths `.` and `:(exclude)flake.lock` unless `flake_lock_explicit` is true.
       - Capture and record the created transfer stash ref.
       - Immediately verify the invoking checkout is clean for the required scope.
       - If required paths remain, stop immediately, report exact remaining paths, and do not continue.
       - Apply the transfer stash into the new worktree with index restoration:

    ```bash
    git -C "$HOME/trees/$repo_name/$new_worktree_name" stash apply --index "$transfer_stash_ref"
    ```

       - If stash apply fails, stop immediately, report stderr and the stash ref, and do not continue.
       - Never drop transfer stashes automatically; keep them available for recovery.
    17. Set the active directory to the new worktree in `worktree_atomic` mode, or the verified task worktree when reusing an existing branch.
    18. Run preflight checks, stage exact files, draft/confirm message when needed, and commit.
    19. If `cleanup_source_paths=true` and `reuse_existing_branch=false`, clean requested paths in the invoking checkout after commit:
       - For tracked files, run `git -C "$invoking_checkout" restore --source=HEAD -- <path>`.
       - For untracked files, run `rip "$invoking_checkout/<path>"`.
       - Verify with `git -C "$invoking_checkout" status --porcelain --untracked-files=all -- <requested_paths...>`.
       - If any requested path remains dirty, stop and report exact paths.
    20. If `push_required`, push safely with upstream tracking.
    21. If PR publication is authorized and an existing PR is in scope, update its title and description to match the final implementation and validation. Otherwise, if `pr_required`, create the requested PR.
    22. Because `pr_required` implies `labels_required`, always set labels immediately after PR creation:
       - Prefer user-provided labels.
       - Otherwise inspect `gh label list` and apply best-matching existing labels.
    23. Return the active path, branch, commit SHA, selected mode, and push/PR outcome.

    ## Handle Failures

    Surface failures and inspect their cause. Retry routine recoverable failures within the authorized scope, including a hook that refreshes generated files and requests a retry. Preserve hooks and unrelated work.

    If recovery needs a destructive action or an unresolved scope decision, report the command, error, current publication state, and the specific decision needed. Do not treat a recoverable failure as a reason to request approval already granted.
  '';
in
{
  flake.lib.agents._internal.skills.raw.commit = {
    name = "commit";
    title = "Git Commit Skill";
    description = "Commit scoped changes in a fresh worktree for new tasks or the verified branch of an existing task or PR; require explicit current-branch authorization for main/master.";
    body = commitSkillBody;

    codex = {
      prelude = ''
        Create a well-formatted git commit following all project safety rules and Conventional Commits format.

        ${commitSelectModeSection "$commit"}
      '';
      openaiYaml.interface = {
        display_name = "Commit Workflow";
        short_description = "Safe commit, push, branch, and PR workflow";
        default_prompt = "Use $commit to complete the authorized commit and publication scope. Create a worktree for new work or continue the verified branch of an existing task or PR. Require explicit current-branch authorization for main/master.";
      };
    };

    claude = {
      frontmatter = {
        "disable-model-invocation" = true;
        "allowed-tools" =
          "Bash(git status*), Bash(git diff*), Bash(git log*), Bash(git add *), Bash(git commit *), Bash(git worktree *), Bash(git stash *), Bash(git restore *), Bash(git ls-files *), Bash(git for-each-ref *), Bash(git rev-parse *), Bash(git branch *), Bash(git push *), Bash(mkdir *), Bash(rip *), Bash(gh repo view *), Bash(gh pr *), Bash(gh label *), Read, Grep, Glob";
        "argument-hint" = "[optional commit message]";
      };
      prelude = ''
        Create a well-formatted git commit following all project safety rules and Conventional Commits format.

        ${commitSelectModeSection "/commit"}

        ## Current Git State

        Working tree status:
        !`git status --short`

        Already staged changes:
        !`git diff --staged --stat`

        Recent commits (for style reference):
        !`git log --oneline -5`

        ### If `$ARGUMENTS` is provided

        Use the provided text as the commit message directly. Still run through safety checks before committing.
      '';
    };
  };
}
