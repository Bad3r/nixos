# Managing the documentation lifecycle

## Publishing

- Documentation releases MUST align with the product release that introduces or changes the documented behavior; docs that ship later than the feature mislead users.
- A single named approver MUST be responsible for blocking or releasing each doc change; diffuse approval produces stalled or broken releases.
- Release-blocking criteria MUST be set in advance and written down (e.g. block on user-harm or data-loss-class issues; do not block on cosmetic typos).
- Apply code-review standards to documentation changes: peer review, version control, CI; documentation that bypasses review will rot.
- Manually rehearse the publication tooling at least once before relying on it for a release; tooling gaps surface only on the first real run.
- Announce material doc changes through existing release-note channels; readers should not need a separate doc-release feed.

## Feedback

- Provide a page-level feedback channel that pre-fills the URL and title; feedback that requires the user to retype context will not arrive.
- Integrate documentation feedback with the team's support and ticket queues; recurring support issues MUST surface as documentation gaps.
- Apply a triage schema to every feedback item: P0 emergency (data loss, security, broken core flow), P1 release-blocker, P2 wanted, P3 not time-sensitive.
- Reject feedback items that are duplicates, irreproducible, or out of scope; rejection MUST include a reason recorded on the issue.
- Close the loop with the original reporter when an item is resolved; the loop is the incentive that produces the next report.

## Measurement

- Define documentation quality as "the document fulfills its purpose"; without that anchor, no metric is meaningful.
- Functional quality (accessible, purposeful, findable, accurate, complete) outranks structural quality (clear, concise, consistent); fix functional defects first.
- Reading level SHOULD measure at or below 10th grade on Flesch-Kincaid (or equivalent) for general-developer audiences.
- For getting-started docs, track Time to Hello World (TTHW); a rising TTHW is the strongest single signal of doc decay.
- Establish a baseline metric before making a change; a "before" without numbers cannot show an "after".
- Use clusters of metrics, never a single metric in isolation; page views without bounce rate or task-completion rate misleads.
- Correlate support ticket volume to specific doc pages; pages that generate disproportionate tickets are accuracy defects, not popularity wins.

## Maintenance

- Every doc page MUST have exactly one named owner accountable for accuracy and freshness; record ownership in `CODEOWNERS` or a metadata header.
- A freshness-review interval (e.g. 6 months) MUST trigger owner re-certification; a doc with no review trigger is unowned.
- A broken-link checker MUST gate CI; a 404 in published docs is a release defect.
- A prose linter SHOULD run in CI for style consistency, terminology drift, and exclusionary language.
- Reference documentation SHOULD auto-generate from source on every release; hand-maintained reference is the largest single source of doc-versus-code drift.
- Build doc maintenance into sprint estimates and performance expectations; treating docs as "extra work" guarantees rot.

## Deprecation

- A deprecation callout MUST appear at the top of any deprecated page, stating the deprecation date and the replacement target; readers MUST see deprecation before content.
- A migration guide MUST be published before the deprecation is announced; never leave users without a forward path.
- Set up redirects on every URL move or removal; deletion without redirects strands users on 404s and search results.
- Remove a deprecated page only when usage is low and issue rate is high, or when the underlying feature is fully removed; popularity alone is not a reason to keep a misleading page.
- Document the deprecation timeline (announce date, end-of-support date, removal date) on the page itself; readers MUST be able to plan from the page without external context.
- A removed page's URL MUST 301 to the closest replacement, not to a generic landing page; landing-page redirects discard the user's intent.
