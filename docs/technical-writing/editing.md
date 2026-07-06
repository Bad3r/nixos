# Editing documentation

## Editing passes

- Edit in distinct passes, in this order: technical accuracy, completeness, structure, clarity, brevity.
- One pass MUST focus on one aspect; combining passes causes all of them to suffer.
- The technical-accuracy pass MUST involve executing every procedure and every code sample as a new user would, not as the author.
- The structure pass MUST verify that title, headings, and section ordering signpost the document; if the outline reads like a maze, the document is too complex or contains multiple goals.

## Peer review

- Peer review is mandatory; self-review misses gaps due to curse-of-knowledge bias regardless of the author's experience.
- A subject-matter technical reviewer MUST be assigned for any topic outside the author's direct expertise.
- Reviewers verify that documented behavior matches actual product behavior; assertions without verification do not count as review.

## Feedback discipline

- Apply the "plussing" rule: a criticism MUST come with a specific suggestion, otherwise it is not actionable feedback.
- Critique the document, never the author; review comments target text, not people.
- When reviewers disagree, resolve by asking "what does the user need?" and document the answer in the review thread.

## Style consistency

- Define each product, feature, and domain term once and use the same form throughout; alias-free terminology is the cheapest correctness gain.
- Adopt one external style guide (Chicago, AP, Google Developer, or similar) and reference it by name in the team's writing notes; do not reinvent grammar rules locally.
