# Visual content

## Comprehension

- Every visual MUST be introduced in body text; a standalone image without prose context is a documentation defect.
- Each diagram MUST illustrate exactly one idea at one level of abstraction; split overloaded diagrams.
- Use a consistent shape vocabulary across diagrams (rectangle = process, diamond = decision, cylinder = store); switching shapes mid-docset breaks reader pattern matching.
- Avoid crossing lines, unlabeled arrows, and unspelled acronyms; have one non-author review the diagram for understandability before publishing.

## Accessibility

- Alt text MUST describe the visual as prose ("Flowchart routing requests through the rate limiter to either the cache or the API"), never "image of X" or "diagram".
- Color contrast MUST meet WCAG ratio of at least 4.5:1 for text and 3:1 for graphical objects.
- Color MUST NOT be the sole carrier of meaning; pair every color distinction with a label, pattern, or shape.
- Video content MUST ship with captions and a text transcript; un-captioned video fails accessibility and search.

## Performance and format

- Use SVG for diagrams and icons; SVG scales without pixelation, zooms cleanly, and stays small.
- Size and place visuals so they remain legible on mobile widths; layout that only works on desktop is a defect.

## Screenshots

- Include enough surrounding UI to orient the reader (window chrome, breadcrumb, sibling controls); a screenshot cropped tight to the click target is disorienting.
- Never embed copy-paste data (URLs, IPs, tokens, code, commands) inside an image; users cannot select or search image text.
- Treat all screenshots as expiring assets; product UI drifts faster than written prose.

## Video

- Avoid video by default; video is expensive to maintain, slow to scan, and a poor fit for reference content.
- If video is justified, the page MUST also offer a written equivalent so readers can skim and copy.
