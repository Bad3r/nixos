### Type

chore

### Scope

ci

### Summary

Negative coverage: comparators other than `>=` and `>` are rejected by the parser and surface as a template-drift warning.

### Unblock condition

Unblocked when the parser stops accepting unsupported comparators -- this fixture exists to lock that behavior in.

### Upstream pull requests

none

### Upstream issues

none

### Upstream releases and channels

blocker https://github.com/anthropics/claude-code-action/releases - target < v1.0.113

### Local workaround / affected code

.github/scripts/upstream-tracker.sh

### Exit criteria

- [ ] Parser keeps rejecting `<`, `<=`, `=` comparators

### Validation

### Notes

### Confirmations

- [x] placeholder
