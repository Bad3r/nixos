# Writing code samples

## Trustworthiness

- Write a sample so it runs unmodified except for clearly marked placeholders.
- Show command output exactly as it prints.
  A reader compares it verbatim against their own.
- Call out a non-obvious result or side effect of a sample.
  Do not rely on the reader to infer it.

## Conciseness

- Keep sample lines short enough to read without horizontal scrolling.
- Elide a region that is not the subject of the sample with `...`.
  The omission must be obvious to the reader.
- Strip a sample to the minimal example.
  Drop setup, error handling, and styling the lesson does not need.

## Naming and placeholders

- Name a placeholder for what it holds, such as `replace-with-api-key`.
  Never use `foo`, `bar`, or `baz`.
- Format a sample with the language's own formatter, such as `gofmt` or `rustfmt`.
  A style violation distracts from the lesson.
