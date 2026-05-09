# Defining scope and audience

## Audience and goals

- Every document MUST have one stated user goal (task outcome) and one stated organizational goal (business outcome); list both at the top of the planning notes, not in the doc itself.
- Pick at most 3-5 user archetypes per product surface; documenting for everyone produces docs for no one.
- Validate audience assumptions against support tickets, search logs, or a friction log before drafting; intuition about what users need is unreliable.
- A friction log MUST be a first-person walkthrough of the product as a new user, recorded as written, with confusion points captured verbatim.
- When user research is unavailable, name the assumed user and their assumed prior knowledge in the planning notes so reviewers can challenge it.

## Content type selection

- Match content to user need: getting-started for discovery to first action, how-to for a specific task, reference for lookup, conceptual for understanding, troubleshooting for fixing.
- Each document MUST serve exactly one type; mixed types signal that the document needs to be split.
- A how-to MUST fit in 10 or fewer numbered steps; longer procedures indicate product complexity that should be questioned, not documented around.
- Prerequisites MUST be stated upfront ("requires admin access", "requires Nix 2.18+"); they act as an early filter for the wrong audience.
- Reference docs SHOULD be auto-generated from source (OpenAPI specs, doc comments, type signatures); hand-maintained reference decays faster than the code it describes.
- Troubleshooting and error-message tables MUST be searchable by the exact error string; users paste error text into search, not paraphrases.
- Group error/troubleshooting entries by frequency or workflow position, not alphabetically.
- Version applicability MUST be stated explicitly when behavior differs across versions ("applies to v2.1+", "deprecated in v3.0").

## Information architecture

- Choose the IA primitive that matches the content: sequence (chronological/alphabetical), hierarchy (parent-child), or web (cross-linked); few real docsets are pure one type.
- Landing pages MUST link directly to documents, not to more landing pages; minimize click depth.
- Navigation cues (breadcrumbs, side nav, "you are here") SHOULD surface the IA; too many cues compete and create decision fatigue.
- Before adding a new page, run a content assessment on the existing set: keep, remove, update, merge, split.
- Single source of truth beats automated content reuse; duplicating a section to multiple landing pages pollutes search.
- Validate IA with card sorting or a comparable method before migrating content; layout decisions made in isolation tend to hide content from users.
- Every user task MUST have a clear starting page, defined next step, and a verifiable end state.
- Section depth SHOULD stay within 2-3 levels; merge or split sections that fall outside this range.
- 301 redirects MUST be created on every URL move; a 404 is a documentation defect.
- Each top-level section MUST have a named owner accountable for its IA decisions; ownership prevents IA drift.
