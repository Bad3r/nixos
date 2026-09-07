# Documentation style guide

Rules for every hand-written Markdown page in this repository.
The reader is a person with a task in hand first, and an agent looking up a fact second.
When a rule here conflicts with another page in this folder, the rule here wins.

## The value test

A sentence stays only when the reader cannot get its content from the code, the tree, or one command.
A fact the code states clearly is never restated; the page names the file when the reader must open it.
A rule that a check enforces is documented by naming the check, not by repeating the rule.

## Content that never appears

- History: no ISO dates, no narrative of how something changed, no comparison with an earlier state.
  Git history owns it.
- Plans versus reality: only the current truth.
  A value that differs from what was once planned is stated once, without the comparison.
- Status: no markers of completion or progress, no phase tracking, no task lists or item trackers, no counts that drift.
  Issues and pull requests own status.
- Values the code holds: no UUIDs, option values, port numbers, or file-to-option tables.
- Firmware and driver versions: they change with every flash or update.
- Meta commentary: nothing about the page itself, its author, its review, or how a fact was found.
- Filler: hedges, transitions, and reassurance.

The machine-checked phrase list is [banned-phrases.txt](banned-phrases.txt).
A phrase on that list is a symptom; rewording around it while keeping the transient content is still a violation.

## Rationale

A why is one clause attached to the fact it explains, at most one sentence.
Longer rationale belongs in the commit body, in the code comment at the option, or in the external source the page links.

## Shape

- One page, one scope.
  Split a page instead of growing it.
- A page has at most 150 lines, counted on the file.
- Headings go two levels below the title: `##` and `###`.
- No sections named `Status`, `Decisions`, `Open Items`, `Notes`, or `Tasks`.
- A table cell is one short phrase of about 40 characters.
  A sentence in a cell means the content is a list.
- A list item is one or two sentences.
- A paragraph is at most four sentences.
- A command is a fenced block the reader can paste, with the working directory and privilege on the lead line when they matter.
- Commands stay inline; a procedure is never shortened by moving its steps into a script the reader has to open.
- External sources get one link line per page; nothing is quoted from them.

## Prose

- One sentence per line in the source.
  The formatter keeps line breaks, so a diff shows the sentence that changed.
- Present tense for facts, imperative mood for steps.
- No first person; name the code, the host, or the reader.
- ASCII only; no em or en dashes.
- A sentence carries one idea and stays under about 25 words.
- Identifiers that may appear: PCI and USB ids and addresses, drive serial numbers, kernel driver and module names, disk labels, mount points, hostnames.
- Every relative link resolves, and every backticked repository path exists.
  A path in another repository is a link to that repository, not a backticked span, which the hook resolves against this tree.

## Host pages

Each host has four pages under `docs/<host>/`.
They are named `<host>-hardware.md`, `<host>-configuration.md`, `<host>-runbook.md`, and `<host>-troubleshooting.md`.
A runbook or troubleshooting page that outgrows the cap splits by topic into `<host>-runbook-<topic>.md` or `<host>-troubleshooting-<topic>.md`.

### Hardware

Parts: one table row per part with product and model number.
Storage: one row per disk with a letter, device, slot or bus address, serial, and role.
Devices: one row per enumerated device with id, address, and driver.
Constraints: facts that limit operation, such as slots that must stay empty, cooling requirements, firmware settings that must hold, and unstable device naming.
Sources: one link to the external hardware record.

### Configuration

One line per deviation from the hosts-common baseline, grouped by domain: boot and kernel, GPU, storage, network, services, policy.
Each line names the effect and its why-clause; the file that carries it is a link.
Nothing the baseline already provides is listed.

### Runbook

One procedure per `##` section, written for the reader who runs it.
Each procedure opens with a precondition line, gives numbered steps with commands inline, and closes with a verification line.
A procedure written before its first run reads exactly like one that has run.

### Troubleshooting

One `##` section per known failure, named by the symptom the reader sees.
Each section gives the cause in one sentence, the diagnostic command, and the fix.

## Enforcement

The pre-commit hook `docs-style` in `modules/meta/hooks/docs-style.nix` runs on every staged Markdown file.
It is pinned to the pre-commit stage, so the `--hook-stage manual` sweep skips it and an older page comes under the rules when it is next edited.
It fails on more than 150 lines, on a banned phrase outside code, and on a link or backticked repository path that does not resolve.
Exempt paths: `docs/nixos-manual/`, `docs/drafts/`, the generated root `README.md`, any `CLAUDE.md` or `AGENTS.md`, and `tests/`.
`docs/index.md` is a table of contents that grows with every page, so only the line cap skips it; its phrases and links are still checked.
A phrase this list matches in a technical sense rather than a meta sense is committed with `SKIP=docs-style`, never `--no-verify`, which turns off every other pre-commit hook with it.
The hook's behavior is pinned by `tests/docs-style/run.sh`, which runs as the `script-tests-docs-style` flake check.
Run it by hand on chosen files from the repository root:

```sh
nix develop path:. -c pre-commit run docs-style --files docs/technical-writing/style-guide.md
```

A page that fails the cap is split, not compressed into longer lines.
