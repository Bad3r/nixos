/*
  Shared Skill Library

  This module provides flake.lib.skills with:
    - skillDefs: Canonical, agent-agnostic skill definitions
    - renderCodexSkillMd: Render SKILL.md for Codex
    - mkCodexSkillDir: Build a full Codex skill directory (SKILL.md + agents/openai.yaml)
    - renderClaudeSkillMd: Render SKILL.md for Claude Code

  Consumers:
    - modules/hm-apps/codex.nix
    - modules/hm-apps/claude-code.nix
*/
{ lib, ... }:
let
  renderFrontmatter =
    fields: fieldOrder:
    let
      orderedKeys = lib.filter (key: fields ? ${key}) fieldOrder;
      extraKeys = lib.sort builtins.lessThan (
        lib.filter (key: !(lib.elem key fieldOrder)) (lib.attrNames fields)
      );
      keys = orderedKeys ++ extraKeys;
      lines = map (key: "${key}: ${builtins.toJSON fields.${key}}") keys;
    in
    ''
      ---
      ${lib.concatStringsSep "\n" lines}
      ---
    '';

  renderSkillBody =
    {
      title,
      intro ? "",
      sections ? [ ],
      body,
    }:
    let
      sectionBlocks = lib.filter (section: section != "") sections;
      sectionText = lib.concatStringsSep "\n\n" sectionBlocks;
      introText = lib.optionalString (intro != "") "${intro}\n\n";
      sectionsText = lib.optionalString (sectionText != "") "${sectionText}\n\n";
    in
    ''
      # ${title}

      ${introText}${sectionsText}${body}
    '';

  commitSelectModeSection = command: ''
    ## Select Mode

    Always execute in `worktree_atomic` mode. Interpret user intent only as post-commit actions:

    1. `${command}` means commit only (no push, no PR) in a newly created worktree.
    2. `${command} and push` means commit + push + PR + labels from a newly created worktree.
    3. `${command} ... create pull request` means commit + push + PR + labels from a newly created worktree.
    4. `${command} ... explicit branch` uses the provided text as the branch seed, then still creates a brand-new unique branch.
  '';

  commitSkillBody = ''
    If the user provides an explicit commit message argument, use it after checks. If user intent is ambiguous, ask one short clarifying question before mutating state.
    If a user requests a direct commit on `main` or `master`, refuse and continue with a new worktree branch workflow.
    Never reuse an existing worktree path from a prior invocation.
    Never reuse any existing local or remote branch name from a prior invocation.

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

    When the user provides an explicit branch name, treat it as a seed and generate a new unique branch from it.
    Do not infer "same feature" from changed files alone. Resolve branch seed only from explicit user branch text, explicit ticket/issue identifier, or explicit "continue branch X" wording, then generate a new unique branch name.

    ## Enforce Non-Negotiable Safety Rules

    Apply these rules in every mode:

    - Never run `git stash drop` or `git stash clear`.
    - Never run `git reset --hard` unless the user explicitly requests it.
    - Never run `git clean -fd`.
    - Never run `git add -A` or `git add .`; stage explicit file paths only.
    - Never run `git push --force` to `main` or `master`.
    - Never use `--no-verify` or `--no-gpg-sign`.
    - Never run `rm` or `rm -rf`; use recoverable deletion tool `rip` when deletion is required.

    After a pre-commit hook failure, never run `git commit --amend` unless the user explicitly asks to amend the previous commit.

    ## Enforce Main Branch Protection

    Apply this guard before any staging or commit:

    - Never run `git commit` when current branch is `main` or `master`.
    - Never perform commit operations in-place on the primary checkout when it is on `main` or `master`.
    - Always create a new worktree and new non-main branch first, then commit inside that new worktree.

    ## Require Invocation-Local Worktree Creation

    Enforce this gate before any `git add` or `git commit`:

    1. Snapshot existing worktree paths at invocation start:

    ```bash
    git worktree list --porcelain
    ```

    2. Create a brand-new worktree path under `~/trees/repo-name` that did not exist at invocation start.
    3. Re-read `git worktree list --porcelain` and verify the new path appears in the post-create list and was absent in the pre-create list.
    4. Refuse execution if verification fails, or if the selected path existed before invocation.
    5. Refuse execution if the command flow attempts to stage or commit before this verification passes.

    ## Require Invocation-Local Branch Creation

    Enforce this gate before any `git worktree add`, `git add`, or `git commit`:

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
    - Split unrelated concerns into separate commits.

    If nothing is staged, inspect unstaged changes, propose the exact file list to stage, and proceed only after user confirmation.

    ## Write Commit Messages

    Use Conventional Commits format: `type(scope): summary`.

    Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `docs`.

    Choose scope from the primary module/directory/domain affected. Keep summary concise and focused on intent.

    Use a heredoc for multi-line messages:

    ```bash
    git commit -m "$(cat <<'MSG'
    type(scope): summary

    Optional body with context.
    MSG
    )"
    ```

    ## Execute Workflow (Always Worktree-First)

    1. Parse intent flags from the user request:
       - `push_required` for push requests
       - `pr_required` for PR requests
       - `labels_required` when PR labels are requested
    2. Normalize intent flags:
       - If `push_required` is true, force `pr_required=true` and `labels_required=true`.
       - If `pr_required` is true, force `labels_required=true`.
    3. Resolve branch seed in this order:
       - Explicit branch text from user input
       - Explicit ticket/issue id from user input
       - New seed inferred from request slug + established naming style
    4. Select base branch in this order:
       - User-specified base
       - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
       - Fallback `main`, then `master` if present
    5. Compute `repo_name` and `trees_repo_dir`, then ensure `"$trees_repo_dir"` exists.
    6. Capture pre-create worktree list.
    7. Capture pre-create branch list (local + remote refs).
    8. Infer naming style from `~/trees/<repo_name>` and build provisional branch/worktree names from branch seed.
    9. Enforce invocation-local branch creation gate by suffixing until branch name is globally unique against pre-snapshot refs.
    10. Derive `new_worktree_name` from final `new_branch` by replacing `/` with `-`.
    11. Ensure `new_branch` is never `main` or `master`.
    12. If `"$HOME/trees/$repo_name/$new_worktree_name"` already exists, append a deterministic suffix (`-r2`, `-r3`, ...) until unique.
    13. Create worktree and new branch from base:

    ```bash
    git worktree add -b new-branch "$HOME/trees/$repo_name/new-worktree-name" base-branch
    ```

    14. Capture post-create worktree list and verify invocation-local creation gate passed.
    15. Transfer pending edits from the invoking checkout into the new worktree before switching active directory:
       - Detect pending state with `git status --porcelain`.
       - If pending edits exist, create a transfer stash with index preservation:

    ```bash
    git stash push --include-untracked --message "commit-skill-transfer-<nonce>"
    ```

       - Capture the created stash ref and apply it into the new worktree with index restoration:

    ```bash
    git -C "$HOME/trees/$repo_name/$new_worktree_name" stash apply --index "$transfer_stash_ref"
    ```

       - Never drop transfer stashes automatically; keep them available for recovery.
    16. Set the new worktree path as the active working directory for all subsequent commands.
    17. Run preflight checks, stage exact files, draft/confirm message when needed, and commit.
    18. If `push_required`, push safely with upstream tracking.
    19. If `pr_required`, create PR with `gh pr create --fill --base base-branch --head active-branch` unless user provides custom title/body.
    20. Because `pr_required` implies `labels_required`, always set labels immediately after PR creation:
       - Prefer user-provided labels.
       - Otherwise inspect `gh label list` and apply best-matching existing labels.
    21. Return new worktree path, active branch, commit SHA, and optional push/PR outputs.

    ## Handle Failures

    If any command fails:

    1. Stop and report the exact failed command and stderr.
    2. Explain whether commit/push/PR happened or not.
    3. Provide the smallest safe recovery step and continue only after confirmation when state is ambiguous.
  '';

  skillDefs = {
    commit = {
      id = "commit";
      title = "Git Commit Skill";
      body = commitSkillBody;
      targets = {
        codex = true;
        claude = true;
      };

      codex = {
        frontmatter = {
          name = "commit";
          description = "Execute safe Git commit workflows when the user invokes $commit or asks to commit changes. Always create a new git worktree under ~/trees/repo-name and commit there, never directly on main/master. Use for $commit, $commit and push, and $commit in a new branch then push and create a pull request with gh and labels.";
        };
        intro = "Create a well-formatted git commit following all project safety rules and Conventional Commits format.";
        sections = [ (commitSelectModeSection "$commit") ];
        interface = {
          display_name = "Commit Workflow";
          short_description = "Safe commit, push, branch, and PR workflow";
          default_prompt = "Use $commit to create a fresh ~/trees worktree and brand-new branch, commit off main/master, and when pushing always create a PR and apply labels.";
        };
      };

      claude = {
        frontmatter = {
          name = "commit";
          description = "Execute safe Git commit workflows when the user invokes /commit or asks to commit changes. Always create a new git worktree under ~/trees/repo-name and commit there, never directly on main/master. Use for /commit, /commit and push, and /commit in a new branch then push and create a pull request with gh and labels.";
          "disable-model-invocation" = true;
          "allowed-tools" =
            "Bash(git status*), Bash(git diff*), Bash(git log*), Bash(git add *), Bash(git commit *), Bash(git worktree *), Bash(git stash *), Bash(git for-each-ref *), Bash(git rev-parse *), Bash(git branch *), Bash(git push *), Bash(mkdir *), Bash(gh repo view *), Bash(gh pr *), Bash(gh label *), Read, Grep, Glob";
          "argument-hint" = "[optional commit message]";
        };
        intro = "Create a well-formatted git commit following all project safety rules and Conventional Commits format.";
        dynamicSections = [
          (commitSelectModeSection "/commit")
          ''
            ## Current Git State

            Working tree status:
            !`git status --short`

            Already staged changes:
            !`git diff --staged --stat`

            Recent commits (for style reference):
            !`git log --oneline -5`
          ''
          ''
            ### If `$ARGUMENTS` is provided

            Use the provided text as the commit message directly. Still run through safety checks before committing.
          ''
        ];
      };
    };
  };

  renderCodexSkillMd =
    skillDef:
    if !(skillDef.targets.codex or false) then
      throw "Skill '${skillDef.id}' does not target Codex"
    else
      let
        frontmatter = renderFrontmatter skillDef.codex.frontmatter [
          "name"
          "description"
        ];
        body = renderSkillBody {
          inherit (skillDef) title;
          intro = skillDef.codex.intro or "";
          sections = skillDef.codex.sections or [ ];
          inherit (skillDef) body;
        };
      in
      ''
        ${frontmatter}

        ${body}
      '';

  renderCodexOpenaiYaml =
    skillDef:
    if !(skillDef.targets.codex or false) then
      throw "Skill '${skillDef.id}' does not target Codex"
    else
      let
        interface = skillDef.codex.interface or { };
        requiredFields = [
          "display_name"
          "short_description"
          "default_prompt"
        ];
        missingFields = lib.filter (field: !(interface ? ${field})) requiredFields;
      in
      if missingFields != [ ] then
        throw "Skill '${skillDef.id}' missing Codex interface fields: ${lib.concatStringsSep ", " missingFields}"
      else
        ''
          interface:
            display_name: ${builtins.toJSON interface.display_name}
            short_description: ${builtins.toJSON interface.short_description}
            default_prompt: ${builtins.toJSON interface.default_prompt}
        '';

  mkCodexSkillDir =
    pkgs: skillDef:
    if !(skillDef.targets.codex or false) then
      throw "Skill '${skillDef.id}' does not target Codex"
    else
      let
        skillMdFile = pkgs.writeText "codex-skill-${skillDef.id}-SKILL.md" (renderCodexSkillMd skillDef);
        openaiYamlFile = pkgs.writeText "codex-skill-${skillDef.id}-openai.yaml" (
          renderCodexOpenaiYaml skillDef
        );
      in
      pkgs.runCommand "codex-skill-${skillDef.id}" { } ''
        mkdir -p "$out/agents"
        cp ${skillMdFile} "$out/SKILL.md"
        cp ${openaiYamlFile} "$out/agents/openai.yaml"
      '';

  renderClaudeSkillMd =
    skillDef:
    if !(skillDef.targets.claude or false) then
      throw "Skill '${skillDef.id}' does not target Claude Code"
    else
      let
        frontmatter = renderFrontmatter skillDef.claude.frontmatter [
          "name"
          "description"
          "disable-model-invocation"
          "allowed-tools"
          "argument-hint"
        ];
        body = renderSkillBody {
          inherit (skillDef) title;
          intro = skillDef.claude.intro or "";
          sections = skillDef.claude.dynamicSections or [ ];
          inherit (skillDef) body;
        };
      in
      ''
        ${frontmatter}

        ${body}
      '';
in
{
  flake.lib.skills = {
    inherit
      skillDefs
      renderCodexSkillMd
      mkCodexSkillDir
      renderClaudeSkillMd
      ;
  };
}
