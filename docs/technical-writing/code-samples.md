# Writing code samples

## Trustworthiness

- Every executable sample MUST run unmodified except for clearly marked configuration values; CI MUST execute the sample on every change.
- Explanatory output (returned values, error messages) MUST match production verbatim; users search for error strings and expect exact matches.
- Pin versions explicitly in samples (language version, dependency version, API version); a sample without a version is a sample that will silently rot.

## Conciseness

- Source lines SHOULD NOT exceed 80 characters where the language's idiomatic style guide allows; horizontal scroll is friction on every device. When the language style guide mandates a wider limit (e.g. `rustfmt` 100), the language style guide wins.
- Use `...` to elide regions that are not the subject of the sample; the omission MUST be obvious to the reader.
- Each sample MUST be a minimal reproducible example; strip unrelated setup, error handling, and styling that does not bear on the lesson.

## Naming and placeholders

- Placeholders MUST be self-describing (`replace_with_api_key`, `your-bucket-name`); never `foo`, `bar`, `baz`, or single-letter names.
- Sample code MUST follow the language's idiomatic style guide (PEP 8, gofmt, rustfmt, etc.); style violations distract from the content.

## Explanation

- Surrounding prose MUST explain the "why" of a sample: intent, tradeoffs, and constraints; never narrate the "what" the code already states.
- A non-obvious result, side effect, or failure mode MUST be called out explicitly; do not rely on the reader to infer it.

## Layering and autogeneration

- When a topic has progressive complexity, present samples in order: hello-world, intermediate, advanced; do not interleave levels on the same page.
- Reference documentation SHOULD auto-generate from source (OpenAPI, Javadoc, rustdoc, doc comments); hand-maintained reference is the leading source of doc-versus-code drift.
