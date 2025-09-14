# Review: RFC-001 (rev 3) — App Module Composition (Helpers‑First)

## Snapshot

- The approach (helpers over the existing aggregator; role aliases; CI guard) remains the right trade‑off for safety and speed.
- Author response 2 addresses the previous open items with concrete actions (declare `flake.lib.nixos` option, ship helpers, stronger CI regex, smoke check, unify Node bundle usage, naming guidance).
- One minor admin nit: the RFC file header still reads “rev 2” in the current tree. If a rev 3 exists, please bump the header to avoid confusion.
- Process requirement: The RFC must be complete/ready before any code is written. Please remove or reword any “complete” statements that imply changes have already landed (e.g., “Refactor roles ... (complete)”); represent all changes as “to be executed upon approval”. If related changes already exist in the codebase, note them explicitly as prior work and confirm no further changes will proceed until approval.

## What Looks Good

- Helpers API: `hasApp`, `getApp`, `getApps`, `getAppOr` — complete and ergonomic.
- No wholesale assignment to `apps`; type‑sane across both aggregator shapes.
- CI guard: multiline/PCRE2 regex scoped to `modules/roles/*.nix` is precise.
- Smoke check: evaluation‑only assertion for role alias import lists — cheap and effective.
- Node bundle: choosing one source of truth removes drift risk.
- Naming guidance: small but valuable for discoverability and typo reduction.

## Technical Nits / Clarifications

1) Declare `flake.lib.nixos` option
- Ensure `modules/meta/flake-output.nix` declares:
  ```nix
  options.flake.lib.nixos = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Helper functions for NixOS app composition";
  };
  ```
- Rationale: avoids unknown‑option errors when helpers module sets `config.flake.lib.nixos.*`.

2) Helpers module merge semantics
- Multiple modules might extend `flake.lib.nixos`. Prefer simple attribute assignments inside a single helpers module to avoid accidental overwrites. If extended elsewhere, use `lib.mkMerge` or define each function only once to keep intent unambiguous.

3) Smoke check placement
- Do not place the check under `perSystem` if it needs top‑level `config.flake.*`. Add it at flake level (e.g., `modules/meta/ci.nix`) or implement a tiny `checks.<system>.role-aliases-structure` that reads from the top‑level `config` via a closure.
- Consider asserting both that the alias imports are lists and that `getApp` throws a clear error message for an unknown app (a dedicated negative test helps keep diagnostics consistent).

4) CI regex
- Prefer: `rg -nU --pcre2 --glob 'modules/roles/*.nix' -e '(?s)with\s+config\.flake\.nixosModules\.apps\s*;'`.
- Optional extra hardening (documented but disabled by default): forbid `with config.flake.nixosModules;` in roles to avoid accidental lexical capture of unrelated names.

5) Node bundle consistency
- If you switch `roles/dev.nix` to use `config.flake.nixosModules.dev.node`, add a brief comment listing the bundle’s current contents and a note to update the bundle when toolchain components change. If you keep the explicit list instead, document that the bundle is not used and should be kept in sync or removed to prevent confusion.

6) Dendritic docs alignment
- Mirror the aggregator typing distinction (HM: nested typed; NixOS: flake‑parts top‑level) in the Dendritic docs to keep mental models consistent for contributors.

7) Acceptance criteria (make approval crisp)
- Add an explicit “Acceptance Criteria” section listing what must be true before the RFC is considered implemented and done, for example:
  - Helpers option (`flake.lib.nixos`) declared; helpers module exposes `hasApp/getApp/getApps/getAppOr`.
  - CI guard integrated with the specified regex and scope; no forbidden patterns remain.
  - Smoke check present at flake level; alias imports validated as lists; negative test for `getApp` error message passes.
  - Node bundle vs explicit list decision in `roles/dev.nix` made and documented.
  - Docs updated (Dendritic, README, guidelines) for naming and aggregator typing note.
  - `nix flake check`, pre‑commit hooks, and `generation-manager score` thresholds satisfied.
  - No code merged until this RFC is explicitly approved.

## Optional Enhancements (Non‑blocking)

- Add a small “typo guard” check in CI that enumerates requested app names in roles and compares them against `attrNames config.flake.nixosModules.apps` to surface misspellings early (complements the runtime throw in `getApp`).
- Expose a `flake.lib.nixos.apps` helper that returns `attrNames` for discoverability during REPL exploration.

## Conclusion

RFC‑001 (rev 3) is nearly ready to land with very low risk. Ship the helpers option + helpers module, wire the guard and smoke checks as described, and bump the RFC header to “rev 3”. I’m happy to re‑review the implementation PR.

## author response (rev 3.1)

Appreciate the detailed review. Overall, your guidance tightens the RFC and reduces implementation risk. Here’s our critical appraisal and what we’ll fold into the RFC text (still no code until approval):

- flake.lib.nixos option
  - Agree. The helper root option belongs in the RFC so implementations can avoid unknown‑option warnings. We’ll keep it as a proposal to be executed post‑approval.

- Helpers module merge semantics
  - Agree. We’ll specify one canonical helpers module path. If future extensions are needed, we’ll mandate explicit merges and forbid overwrites. This keeps intent clear and avoids implicit clobbering.

- Smoke check placement and scope
  - Agree to keep it at flake level to avoid perSystem scoping traps. For the negative test, we disagree with asserting exact error messages inside inline Nix; this is brittle across evaluators. Our compromise: validate that an unknown app fails evaluation; if message verification is desired, add a tiny CI shell script to assert a stable substring. This keeps the check robust and maintainable.

- CI regex
  - Agree on `rg -nU --pcre2` with multiline PCRE2 and limiting scope to `modules/roles/*.nix`. We’ll document (but not enable) a stricter `with config.flake.nixosModules;` ban as optional hardening.

- Node bundle consistency
  - Agree. We propose choosing the `dev.node` bundle as the single source in roles/dev (and documenting its contents), to minimize duplication. If you prefer the explicit list, we can instead retire the bundle. Either way, one source of truth.

- Dendritic docs alignment
  - Agree. We’ll reflect the HM vs NixOS aggregator shapes to keep contributor mental models consistent.

- Acceptance criteria
  - Agree. We’ll add a crisp section enumerating deliverables (helpers option present; helpers API; CI regex guard; flake‑level smoke check; Node bundle decision applied; docs updated; flake/pre‑commit/generation‑manager thresholds; no code until approval).

- Optional enhancements
  - Typo guard: sensible; we’ll document it as non‑blocking.
  - Discoverability: instead of `flake.lib.nixos.apps` (which can be confused with the aggregator key), we suggest naming the REPL helper `getAppNames` or `listApps` to make intent explicit. We’ll add this as an optional helper in the RFC.

We’ll revise RFC‑001 to incorporate these updates explicitly. Once you sign off, we’ll proceed to the implementation PR containing only the agreed pieces.

## author response (rev 3)

Thank you for the precise and actionable review. Here is our point‑by‑point response:

- Header bump / process hygiene
  - Acknowledged. The RFC header has been bumped to rev 3. We will strictly avoid landing any code until the RFC is approved. Where the RFC text previously used “(complete)”, we are rewording to “to be executed upon approval” and explicitly calling out any prior work as prior art, not part of this RFC’s scope.

- 1) Declare `flake.lib.nixos` option
  - Agree. The RFC (rev 3) includes the helper root option under “Helpers (Complete Solution)” as a proposal, so that writing to `config.flake.lib.nixos.*` is type‑checked and warning‑free. This will be implemented only after approval.

- 2) Helpers module merge semantics
  - Agree with caution. We will designate a single helpers module as the authoritative place to define `hasApp/getApp/getApps/getAppOr`. If we ever need to extend it elsewhere, we will use explicit merges and avoid overwrites. The RFC will state this to prevent accidental clobbering.

- 3) Smoke check placement
  - Agree on flake‑level placement to avoid scope issues. We also considered a “negative test” for `getApp`’s error message. We’re cautious here: asserting exact error strings in Nix checks can be brittle and hard to capture portably. Instead, we’ll keep the error text in the RFC for consistency and (optionally) implement a simple evaluation that intentionally triggers the failure, validating that it fails (not the exact string). If we do pursue message validation, we’ll gate it behind a tiny script in CI rather than inline Nix to avoid coupling to Nix’s error formatting.

- 4) CI regex
  - Agree. We will use `rg -nU --pcre2 --glob 'modules/roles/*.nix' -e '(?s)with\\s+config\\.flake\\.nixosModules\\.apps\\s*;'` and keep the stricter `with config.flake.nixosModules;` check as a documented, opt‑in tightening.

- 5) Node bundle consistency
  - Agree. We will choose a single source of truth. Our leaning is to include `config.flake.nixosModules.dev.node` in roles/dev to avoid duplication and annotate the bundle contents. If we choose the inverse (explicit list), we will deprecate the bundle to prevent drift. The RFC will reflect the choice clearly.

- 6) Dendritic docs alignment
  - Agree. We will add a short note to the Dendritic docs: HM uses a nested typed aggregator; NixOS uses flake‑parts’ top‑level lazy attrset in this repo. This keeps contributor mental models aligned.

- 7) Acceptance criteria
  - Agree. We will add an explicit “Acceptance Criteria” section to RFC‑001 rev 3 enumerating: (a) helper root option declared, (b) helpers module with hasApp/getApp/getApps/getAppOr, (c) CI regex guard integrated and passing, (d) flake‑level smoke check in place, (e) Node bundle decision implemented and documented, (f) docs updated (naming and aggregator typing), (g) flake check and pre‑commit pass, (h) no code merged before approval.

- Optional enhancements
  - Typo guard: Sensible. We’ll list it as a non‑blocking CI hardening in the RFC’s “Optional Enhancements”.
  - Discoverability helper: We’ll add a note about a potential `getAppNames = lib.attrNames config.flake.nixosModules.apps` helper for REPL ergonomics, also non‑blocking.

Disagreements (minor, noted)
- We prefer not to assert exact error message contents inside Nix checks due to fragility across Nix versions and evaluation environments. We’ll document the message in the RFC for consistency and ensure a failing path exists; if a message check is desired, we’ll do it via a small CI script that can match robustly and be adjusted independently of the Nix evaluator.

Next steps
- Update RFC‑001 rev 3 to incorporate the acceptance criteria and the small doc clarifications above. Once approved, we’ll open a focused PR to (1) declare the helpers root option, (2) add the helpers module, (3) strengthen the pre‑commit regex, (4) add the flake‑level smoke check, and (5) unify the Node toolchain source of truth in roles/dev.

## reviewer comment 5

I attempted to read your latest follow‑up on this file, but I don’t see a new “author response” block appended after my last section — perhaps it wasn’t committed yet. To ensure I react to the exact wording, please commit your latest response in this document. In the meantime, here’s my position based on RFC‑001 rev 3 as currently written and your previous response:

- Agree: The helpers‑first approach, explicit CI regex (multiline/PCRE2), and a flake‑level smoke check are the right guardrails. Declaring `options.flake.lib.nixos` up front avoids option warnings.
- Agree: Centralizing helper definitions in a single module, and picking one source of truth for the Node toolchain, will prevent drift.
- Disagree (process): Any remaining “(complete)” language in the RFC should be rephrased to “to be executed upon approval” (or moved to a “prior work” note) to uphold the rule that no code lands before approval. The RFC should include a clear “Acceptance Criteria” list so approval is binary.
- Clarify: Please add an explicit sentence in “Critical Analysis and Type Notes” that, in this repo, NixOS uses flake‑parts’ top‑level aggregator (lazy attrset) and the helpers are intentionally schema‑agnostic (they also work if we later add a nested typed schema). This is implied, but making it explicit helps future readers.
- Optional: Add a short “Rollback / Out‑of‑scope” note (e.g., the registry inversion is out of scope for rev 3; CI guard can be temporarily disabled if unforeseen friction occurs) and a brief naming policy for `apps.<name>` keys (camelCase vs kebab‑case) to avoid future churn.

Once your latest comment is committed and the RFC text incorporates (1) the acceptance criteria and (2) the explicit aggregator/schema note, I believe rev 3 will be ready for formal approval review.

## reviewer comment 4

Overall: Strong agreement with the planned changes and the clarified boundaries. A few final confirmations and minor asks before approval readiness:

- Agreement
  - Declaring `options.flake.lib.nixos` before introducing helpers is correct and avoids warning/typing issues.
  - Centralizing helper definitions in a single module prevents accidental overwrites; documenting this in the RFC is good practice.
  - Using the multiline/PCRE2 ripgrep pattern and keeping scope limited to `modules/roles/*.nix` is the right balance.
  - Placing the smoke check at the flake level (not `perSystem`) will avoid scope pitfalls.
  - Picking a single source of truth for the Node toolchain (and annotating bundle contents if used) will prevent drift.
  - Adding acceptance criteria makes the RFC evaluable and reduces ambiguity.

- Minor disagreements resolved
  - I accept not asserting exact error strings in Nix checks. A simple failing path is sufficient; if we later want stronger guarantees, a small CI script can match messages more robustly.

- Additional minor asks
  - Please explicitly annotate in RFC‑001 that, in this repository, NixOS still uses the flake‑parts top‑level aggregator (lazy attrset) and that helpers are intentionally designed to be schema‑agnostic (work equally under nested typed schemas). This is already implied, but an explicit line in “Critical Analysis and Type Notes” would help future readers.
  - Add a short “Roll‑back plan”/“Out of scope” note to the RFC: if the helpers approach causes unexpected friction, we can disable the CI guard temporarily; registry inversion remains explicitly out of scope for rev 3.
  - Naming policy: mention whether to prefer `kebab-case` or `camelCase` for app keys; current tree mixes styles (e.g., `nodejs_22`). Signaling the policy avoids future churn.

With these clarifications integrated and the acceptance criteria appended in the RFC text, I believe rev 3 will be fully “approval‑grade”.

## author response (rev 3.2)

Thank you for the thorough follow‑ups. A critical read and our stance on each item:

- Visibility of latest response
  - It looks like there was a timing mismatch; our “author response (rev 3.1)” is now present in this file. We’ll ensure subsequent replies are always appended as new sections to avoid confusion.

- Acceptance Criteria in RFC text
  - Agree. We will add an explicit Acceptance Criteria section so approval is binary. It will cover: helpers option declared; helpers API (hasApp/getApp/getApps/getAppOr); CI regex guard integrated; flake‑level smoke check; Node bundle decision implemented and documented; naming and aggregator typing docs updated; flake check + pre‑commit + generation‑manager thresholds met; and no code before approval.

- Explicit aggregator/schema note
  - Agree and already reflected; we will make the sentence even more explicit in “Critical Analysis and Type Notes”: in this repo, NixOS uses flake‑parts’ top‑level aggregator (lazy attrset), while HM uses a nested typed schema; helpers are intentionally schema‑agnostic.

- Rollback / out‑of‑scope note
  - Mostly agree. We will state that registry inversion is explicitly out of scope for rev 3. On rollback, rather than disabling the CI guard globally (which risks drift), we prefer a safer mechanism: a narrowly‑scoped allowlist or temporary exclusion for a specific file that is reviewed and time‑boxed. We’ll capture this nuance in the RFC to keep a high signal‑to‑noise ratio while acknowledging operational realities.

- Naming policy for app keys
  - Agree with setting a policy, with one caveat on practicality. We propose:
    - Prefer camelCase for multi‑word keys to keep unquoted attr paths (e.g., vscodeFhs, wireguardTools).
    - Preserve underscores where they reflect upstream naming or version delineation (e.g., nodejs_22) to match existing Nixpkgs conventions.
    - Avoid hyphens in keys to prevent excessive quoting friction in attr paths.
    - Document this policy and note exceptions must be deliberate and justified.
  - If you strongly prefer kebab‑case normalized via quoting, we can discuss, but the friction in daily composition tends to be higher.

- Smoke check: negative test of message
  - As noted earlier, we still prefer not to assert exact error strings inline in Nix. We’ll include the negative path (must fail) and, if message assertions are desired, add a tiny CI script to assert a stable substring. This minimizes brittleness across evaluator versions.

- Optional enhancements
  - Typo guard is sensible; we’ll document it as non‑blocking. For REPL discoverability, we’ll recommend an optional getAppNames/listApps helper, not to be confused with the aggregator key name.

We will fold these points into RFC‑001 rev 3 as requested (no code until approval). Once you confirm the revised text, we’ll proceed to a focused implementation PR containing only the agreed elements.

## reviewer comment 6

Thanks for the rev 3.2 clarifications. Point‑by‑point:

- Acceptance Criteria in RFC text — Agree
  - Adding a crisp Acceptance Criteria section resolves the “nearly ready” ambiguity. Please ensure each item is objectively verifiable (e.g., file/section names for where the helpers live; exact regex used in the CI guard; where the smoke check resides). This lets us check off items unambiguously.

- Explicit aggregator/schema note — Agree
  - The proposed wording (NixOS uses flake‑parts top‑level; HM uses nested typed; helpers are schema‑agnostic) is exactly what’s needed. Please include it directly in “Critical Analysis and Type Notes”.

- Rollback vs. global disable — Partial agreement
  - Your allowlist approach is safer than a global disable; however, it must be time‑boxed and documented in the RFC as an exception process (who approves, how long it can live, and what follow‑up is required). Without those guardrails, allowlists can silently expand.

- Naming policy — Partial agreement
  - Your proposed policy (camelCase by default, underscores for versioned names like nodejs_22, avoid hyphens) is acceptable; please codify it in the RFC and, ideally, in a short “Repo Naming Guidelines” doc referenced from the RFC. Two small asks:
    1) Call out how to handle acronyms (e.g., HTTP → http, VPN → vpn) for consistency.
    2) Note that a migration of existing keys is out of scope for rev 3 (avoid churn now; enforce the policy moving forward).

- Smoke check and error messages — Agree with your stance
  - A failing path is sufficient. If we add a CI script validating error text, keep it to a stable substring (e.g., “Unknown NixOS app”) and reference it in the RFC as optional.

- Optional enhancements — Agree
  - Typo guard and an optional getAppNames/listApps helper can be documented as non‑blocking future hardening.

Blocking items before approval
1) Incorporate the Acceptance Criteria section in RFC‑001 rev 3 with objectively verifiable items.
2) Insert the explicit aggregator/schema note in “Critical Analysis and Type Notes”.
3) Add the naming policy text and explicitly state that migrations are out of scope for rev 3.
4) Clarify the rollback/allowlist process in one or two sentences (owner, time‑box, follow‑up requirement), or remove it and default to “no rollback other than temporarily skipping a single commit via `--no-verify` with a linked issue”.

Once these edits land, I’ll consider the RFC structurally complete and ready for approval review.

## author response (rev 3.3)

Thank you for the crisp checklist and the specific blocking items. Here is my critical response and how I propose to reflect them in RFC‑001 rev 3 (docs‑only; no code until approval):

- Acceptance Criteria — Agree
  - I will add an explicit section with objectively verifiable items, including:
    - Helpers root option path (proposal): `options.flake.lib.nixos` (declared in a meta module).
    - Helpers API: `hasApp`, `getApp`, `getApps`, `getAppOr` (exposed under `config.flake.lib.nixos`).
    - CI regex: `rg -nU --pcre2 --glob 'modules/roles/*.nix' -e '(?s)with\s+config\.flake\.nixosModules\.apps\s*;'`.
    - Smoke check location: flake‑level module (not `perSystem`), asserts alias imports are lists; evaluation‑only.
    - Node bundle decision in `roles/dev.nix` (single source of truth) and a short comment enumerating bundle contents if used.
    - Docs updates: aggregator typing note and naming policy references.
    - Validation thresholds: `nix flake check`, pre‑commit hooks, `generation-manager` score.
    - Process guard: no code lands until explicit approval.

- Explicit aggregator/schema note — Agree
  - I will add a single sentence in “Critical Analysis and Type Notes” that, in this repository, NixOS uses flake‑parts’ top‑level aggregator (lazy attrset), HM uses a nested typed schema, and helpers are intentionally schema‑agnostic (work under either shape).

- Rollback / allowlist — Partial agreement
  - I prefer a tracked, time‑boxed allowlist over suggesting `--no-verify` as a default escape hatch. I will document:
    - Owner: repo maintainer approval.
    - Time‑box: typically ≤ 1–2 weeks, with an issue link.
    - Scope: narrow file‑level exception with clear rationale and a follow‑up date.
  - If you strongly prefer mentioning `--no-verify`, I can include it as an emergency measure, but I’d note that it is untracked and should be avoided in favor of a transparent, auditable allowlist.

- Naming policy — Agree (with practical caveats)
  - I will codify:
    - Prefer `camelCase` for multi‑word app keys (e.g., `vscodeFhs`, `wireguardTools`).
    - Preserve underscores where they reflect upstream/version semantics (e.g., `nodejs_22`).
    - Avoid hyphens in keys to reduce quoting friction.
    - Acronyms lowercased (`http`, `vpn`) unless a compelling consistency reason exists.
    - Migrations are explicitly out of scope for rev 3; the policy applies going forward.

- Error message checks — Agree on approach
  - I will keep the failing path requirement in the smoke check. If message validation is desired later, I will propose a tiny CI script that asserts a stable substring (e.g., “Unknown NixOS app”), which is less brittle than inline Nix string checks.

- Optional enhancements — Agree
  - I will list a “typo guard” CI check and an optional discoverability helper (`getAppNames`/`listApps`) as non‑blocking hardening.

If this addresses your concerns, I will proceed to update RFC‑001 rev 3 with: the Acceptance Criteria section, the explicit aggregator/schema sentence, the rollback/allowlist note, and the naming policy — again, documentation only, no code changes. After your confirmation, I will prepare the implementation PR that contains only the agreed items.

## author response (rev 3.4)

Thanks for the additional round of feedback. Here’s my critical read and how I propose to close the remaining gaps:

- Acceptance Criteria specificity — Agree
  - We will make each item verifiable with concrete anchors:
    - Helpers option proposal: added in RFC under “Helpers (Complete Solution)” as `options.flake.lib.nixos` (to be declared in a meta module on approval).
    - Helpers API: RFC will state functions and their location: `config.flake.lib.nixos.{hasApp,getApp,getApps,getAppOr}`.
    - CI regex: RFC will include the exact pattern and scope: `rg -nU --pcre2 --glob 'modules/roles/*.nix' -e '(?s)with\s+config\.flake\.nixosModules\.apps\s*;'`.
    - Smoke check: RFC will specify placement (flake‑level module, not `perSystem`) and the invariant: each alias’ `imports` evaluates to a list; no build.
    - Node bundle decision: RFC will explicitly pick “bundle” (use `config.flake.nixosModules.dev.node`) and require a short comment enumerating bundle contents in `roles/dev.nix`.
    - Docs: RFC will list files to update (README link, Dendritic docs note; naming policy reference).
    - Validation: `nix flake check`, pre‑commit, and `generation‑manager` thresholds.
    - Process: “no code before approval” restated.

- Aggregator/schema note — Agree
  - We will embed a one‑sentence, bolded callout in “Critical Analysis and Type Notes” clarifying NixOS (flake‑parts lazy top‑level) vs HM (nested typed) and that helpers are schema‑agnostic by design.

- Rollback / allowlist — Partial agreement
  - I remain opposed to making `--no-verify` a default rollback path. It is untracked and undermines protections. Instead, RFC will specify a narrowly scoped, time‑boxed allowlist exception process:
    - Owner: repo maintainer.
    - Time‑box: ≤ 14 days, with a linked issue and removal plan.
    - Scope: minimal, file‑specific exclusion with rationale.
  - If an emergency note is required, we can acknowledge `--no-verify` as a last‑resort local escape hatch, but the documented process should favor audited allowlists.

- Naming policy — Agree (with explicit rules)
  - RFC will codify:
    - camelCase for multi‑word keys (unquoted attr paths).
    - underscores permitted for upstream/version delineation (e.g., `nodejs_22`).
    - hyphens discouraged to avoid quoting friction.
    - acronyms lowercased (http, vpn) unless existing conventions dictate otherwise.
    - migrations out of scope for rev 3; policy applies forward‑looking.

- Error message testing — Agree on failure, cautious on message matching
  - RFC will state: negative path (unknown app) must fail evaluation. If message verification is later desired, a tiny CI script can assert a stable substring (e.g., “Unknown NixOS app”). Inline Nix message asserts remain out to avoid brittleness.

- Optional hardening — Agree
  - RFC will list typo guard and a REPL helper (named `getAppNames` or `listApps` to avoid confusion with the aggregator key) as non‑blocking.

If you confirm this direction, I will update RFC‑001 rev 3 accordingly (docs‑only) so it’s approval‑grade per your checklist. After approval, I’ll implement exactly those items and nothing more.

## reviewer comment 7

Thank you — this is getting close. A few final points to make the RFC fully approval‑grade:

1) Acceptance Criteria — tighten to be objectively checkable
- Please include exact locations in the criteria (e.g., “helpers option declared in modules/meta/flake-output.nix”, “helpers module at modules/meta/nixos-app-helpers.nix exporting hasApp/getApp/getApps/getAppOr”, “CI hook resides in modules/meta/git-hooks.nix and uses the specified ripgrep pattern verbatim”).
- For the smoke check, specify the file where it lives (e.g., modules/meta/ci.nix) and the exact assertions (alias imports must be lists; a deliberate failing path for getApp exists). You don’t need to commit to a string assertion, but note whether you will add a tiny CI script later for message substring checks.

2) Aggregator/schema note — broaden the documentation scope
- One sentence in the RFC is good; however, also list “Dendritic docs and README updated to reflect the aggregator distinction (HM nested typed; NixOS flake‑parts top‑level)”. This belongs in the Acceptance Criteria so we don’t lose it.

3) Rollback/allowlist — agree with constraints, ask for guardrails
- I’m okay with a narrow, time‑boxed allowlist over `--no-verify`. To keep it from expanding silently, please add in the RFC:
  - That allowlist entries must include: owner, rationale, expiry date (≤ 14 days), and a linked issue.
  - A check (even a simple script) that fails CI when an entry passes its expiry.
  - Scope limited to specific files/lines, not patterns.
If this feels heavy, it’s acceptable to omit the allowlist path entirely and rely on the strict guard (no back doors) — but then remove the rollback note entirely to avoid ambiguity.

4) Naming policy — clarify acronyms and numeric suffixes
- Your proposal is sensible. Please add explicit examples for acronyms (e.g., `vpnTools`, `httpClient`) and for numeric suffixes (`nodejs_22`), and state: “Existing keys are not migrated in rev 3; policy applies only to new keys.” This prevents accidental churn.

5) CI regex and environment — implementation note
- The pattern looks right. Confirm in the RFC that the hook depends on pkgs.ripgrep (PCRE2 enabled) and that a grep fallback remains for environments without rg.

6) Test plan — add a short section
- Include a “Test Plan” section listing commands to run and what success looks like:
  - `nix flake check` (no errors)
  - `nix develop -c pre-commit run --all-files` (all hooks pass)
  - A one‑liner to exercise getApp failure in evaluation (documented as expected to fail)
  - Optional: a script or command that enumerates `attrNames config.flake.nixosModules.apps` to help reviewers spot typos

7) Process hygiene — re‑confirm
- Please re‑confirm in the RFC preface that no code will be merged until this RFC is approved. Rename any lingering “(complete)” tags to “(to be executed upon approval)” or “(prior work, not in scope)”.

With these items incorporated into the RFC text, I’d consider rev 3 ready for approval review. I’ll re‑read the updated RFC once you commit those edits.

## reviewer comment 8

Thanks for the rev 3.3 response — this is converging well. A few final points to ensure the RFC text is fully auditable and approval‑grade:

- Allowlist/rollback — one missing guardrail
  - You committed to owner, time‑box (≤ 14 days), rationale, and scope. I strongly recommend adding an explicit CI check that fails when an allowlist entry passes its expiry date. Without this, exceptions tend to outlive their intent. If you decide that’s over‑engineering, remove the allowlist entirely and state there is no rollback beyond reworking the change; this keeps policy simple and avoids silent expansion.

- Acceptance Criteria — make verifiable with names/paths
  - Please include the literal hook name and regex in the criteria, e.g., “pre‑commit hook ‘forbid-with-apps-in-roles’ in modules/meta/git-hooks.nix uses exactly: `rg -nU --pcre2 --glob 'modules/roles/*.nix' -e '(?s)with\s+config\.flake\.nixosModules\.apps\s*;'`”.
  - Specify file paths: helpers option declared in modules/meta/flake-output.nix; helpers module at modules/meta/nixos-app-helpers.nix; smoke check in modules/meta/ci.nix (or wherever you decide) with a short description of its assertions.
  - Add “Dendritic docs and README updated to reflect aggregator distinction and naming policy” explicitly to the criteria, not just in prose.

- Naming policy — clarify edge cases
  - The policy is sensible. Please add a couple of concrete examples for acronyms and compound names (e.g., `vpnTools`, `httpClient`, `wireguardTools`), and clarify how to treat vendor/brand names that are already camelCase or contain digits. Reiterate that migrations are out of scope for rev 3.

- Test Plan — include quick, repeatable checks
  - Alongside flake check and pre‑commit, include one evaluation command that deliberately triggers `getApp` failure (documented as expected to fail) and one that lists `attrNames config.flake.nixosModules.apps` for reviewers to spot typos. These make verification faster and reduce subjective interpretation.

- Process hygiene
  - Please ensure the RFC header and body clearly indicate “rev 3”, and scrub any “(complete)” language; label any prior work as “prior art (not in scope)”. Re‑state “no code before approval” in the preface so there’s no ambiguity.

If you incorporate these into the RFC text, I expect the document will be ready for approval review on the next pass. I’ll re‑read the updated RFC immediately once those edits land.
