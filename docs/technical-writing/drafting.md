# Drafting documentation

## Titles and headings

- Titles MUST be verb phrases describing the goal ("Uploading files to S3"), never noun-only labels ("File upload", "S3 functionality").
- Headings serve as signposts for skim readers; a reader who reads only the headings MUST be able to reconstruct the document's outline.
- Use sentence case for all heading levels; avoid title case and ALL CAPS.

## Structure and flow

- Order content as prerequisites, then core task, then verification; never lead with explanation when the user is here to do something.
- Lead with the most important information in the first paragraph; readers skim at roughly 28% of words and decide to leave or stay early.
- Each paragraph MUST express one idea; if a paragraph needs a transition word ("however", "additionally") it usually needs to be split.

## Paragraphs and lists

- Paragraphs SHOULD NOT exceed 5 sentences; long blocks fail on mobile and in skim reading.
- Numbered lists for procedures; each numbered item MUST contain exactly one action.
- Bulleted lists for non-sequential items; order by usefulness or frequency, not alphabetically, unless lookup is the use case.

## Voice and tense

- Write in active voice; passive voice obscures the actor and inflates word count.
- Use the imperative mood for instructions ("Run `nix flake check`", not "The user can run `nix flake check`").
- Address the reader as "you" in second person; avoid first-person plural.
- Use present tense; future tense ("will run") is rarely needed and adds noise.

## Callouts

- Reserve warning, caution, and note callouts for safety-critical or non-obvious information; routine notes belong in prose.
- Alert fatigue degrades all callouts; if a page has more than two callouts, the page itself is the warning.

## Templates

- Use templates for repetitive document types (release notes, API endpoint pages, runbooks); consistency beats per-document creativity for reference content.
- Mark unfinished sections with `[TODO]` or `[FIXME]` and ship the partial draft; iterating against feedback beats withholding for polish.
