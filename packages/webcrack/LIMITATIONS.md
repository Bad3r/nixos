# Bundle Format Detection Notes

## webcrack Supported Formats

webcrack only supports **two** bundle formats:

- **webpack**
- **browserify**

### Browserify Detection Pattern

Looks for this structure:

```javascript
(function(files, cache, entryIds) {...})({
  1: [function(require, module, exports) {...}, {"./dep": 2}],
  2: [function(require, module, exports) {...}, {}]
}, {}, [1])
```

Key signatures:

- IIFE with 3 params: `files`, `cache`, `entryIds`
- Object with numeric keys
- Each module is `[function, dependencies_object]`

### Webpack Detection Pattern

Looks for webpack's runtime with `__webpack_require__` and module array/object.

---

## NOT Supported: esbuild/bun ESM Bundles

Example: Claude Code's `cli.js` is bundled with **bun** (uses esbuild under the hood) in ESM format.

### How to Identify esbuild/bun ESM Bundles

**1. ESM imports at the top:**

```javascript
import { createRequire as XuK } from "node:module";
```

**2. esbuild runtime helper functions:**

```javascript
// __toESM - convert CommonJS to ESM
var r = (A, K, q) => {
  q = A != null ? wuK(HuK(A)) : {};
  let Y = K || !A || !A.__esModule ? kVA(q, "default", { value: A, enumerable: !0 }) : q;
  // ...
};

// WeakMap for caching (esbuild signature)
var cQ6 = new WeakMap;

// __toCommonJS - convert ESM to CommonJS
var cm = (A) => {
  var K = cQ6.get(A);
  // ...
};

// __commonJS - lazy CommonJS wrapper
var v = (A, K) => () => (K || A((K = { exports: {} }).exports, K), K.exports);

// __export - export helper
var p5 = (A, K) => {
  for (var q in K) kVA(A, q, { get: K[q], enumerable: !0, ...});
};
```

**3. Lazy initialization pattern:**

```javascript
var C = (A, K) => () => (A && (K = A((A = 0))), K);
var UE1 = C(() => {
  /* module code */
});
```

**4. No numeric module IDs** - uses variable names instead of `1`, `2`, `3`

---

## Why webcrack Misdetects esbuild as Browserify

webcrack's browserify matcher is loose enough to partially match esbuild's output structure, resulting in:

- Detecting "browserify" type
- Only extracting ~4 modules instead of hundreds
- Leaving 99%+ of code in `deobfuscated.js`

---

## Tools That Might Work for esbuild Bundles

| Tool      | Status | Notes                                           |
| --------- | ------ | ----------------------------------------------- |
| webcrack  | ❌     | Detects as browserify, doesn't split modules    |
| synchrony | ❌     | Doesn't support ESM (`ImportDeclaration` error) |
| wakaru    | ⚠️     | Can process but unpacker produces single file   |
| debundle  | ❌     | Abandoned (8+ years), webpack only              |

---

## Alternative Approaches

1. **Cleanroom reverse engineering** - Document behavior, rewrite from scratch
   - Example: https://github.com/ghuntley/claude-code-source-code-deobfuscation

2. **Manual analysis** - Use the beautified output + pattern extraction scripts
   - `analyze_cli.py` - Extract error messages, API endpoints, env vars
   - `extract_prompts.py` - Extract system prompts

3. **AST-based extraction** - Write custom babel transforms to:
   - Identify esbuild's lazy module wrappers (`var X = C(() => {...})`)
   - Extract and split into separate files
   - Would require significant custom work
