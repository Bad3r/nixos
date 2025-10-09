#!/usr/bin/env node

/**
 * Generate Markdown files for each extracted module.
 *
 * Usage:
 *   node scripts/generate-module-markdown.js \
 *     [.cache/module-docs/modules-extracted.json] \
 *     [.cache/module-docs/markdown]
 */

const fs = require("node:fs");
const path = require("node:path");

const [
  inputPath = ".cache/module-docs/modules-extracted.json",
  outputDir = ".cache/module-docs/markdown",
] = process.argv.slice(2);

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function toMarkdownValue(value) {
  if (value === null || value === undefined) return "null";
  if (typeof value === "string") {
    return value.trim();
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  if (Array.isArray(value)) {
    if (value.length === 0) {
      return "[]";
    }
    return value.map((entry) => `- ${toMarkdownValue(entry)}`).join("\n");
  }

  try {
    return "```json\n" + JSON.stringify(value, null, 2) + "\n```";
  } catch (error) {
    return String(value);
  }
}

function renderOption(optionName, option) {
  const lines = [];
  lines.push(`### ${optionName}`);

  if (option.type) {
    lines.push(`- **Type:** \`${option.type}\``);
  }

  if (Object.prototype.hasOwnProperty.call(option, "default")) {
    const renderedDefault = toMarkdownValue(option.default);
    if (renderedDefault) {
      lines.push("- **Default:**");
      lines.push(renderedDefault);
    }
  }

  if (option.description) {
    lines.push("- **Description:**");
    lines.push(option.description.trim());
  }

  if (
    Object.prototype.hasOwnProperty.call(option, "example") &&
    option.example !== null
  ) {
    const renderedExample = toMarkdownValue(option.example);
    if (renderedExample) {
      lines.push("- **Example:**");
      lines.push(renderedExample);
    }
  }

  lines.push("");
  return lines.join("\n");
}

function renderModule(module) {
  const metadata = {
    path: module.path,
    namespace: module.namespace,
    name: module.name,
    optionCount: module.optionCount ?? 0,
  };

  const frontMatter =
    "---\n" +
    Object.entries(metadata)
      .map(([key, value]) => `${key}: ${value ?? ""}`)
      .join("\n") +
    "\n---\n\n";

  const lines = [frontMatter];

  lines.push(`# ${module.namespace}.${module.name}`);
  lines.push("");

  if (module.description) {
    lines.push(module.description.trim());
    lines.push("");
  }

  if (Array.isArray(module.imports) && module.imports.length > 0) {
    lines.push("## Imports");
    lines.push("");
    module.imports.forEach((imp) => {
      lines.push(`- ${imp}`);
    });
    lines.push("");
  }

  const optionEntries = Object.entries(module.options ?? {});
  if (optionEntries.length > 0) {
    lines.push("## Options");
    lines.push("");

    optionEntries
      .sort(([left], [right]) => left.localeCompare(right))
      .forEach(([optionName, option]) => {
        lines.push(renderOption(optionName, option));
      });
  }

  return lines.join("\n");
}

function main() {
  if (!fs.existsSync(inputPath)) {
    console.error(`Input file not found: ${inputPath}`);
    process.exit(1);
  }

  let data;
  try {
    const raw = fs.readFileSync(inputPath, "utf-8");
    data = JSON.parse(raw);
  } catch (error) {
    console.error(`Failed to read or parse ${inputPath}:`, error);
    process.exit(1);
  }

  const modules = Array.isArray(data.modules) ? data.modules : [];

  ensureDir(outputDir);

  modules.forEach((module) => {
    const namespace = module.namespace || "unknown";
    const dir = path.join(outputDir, namespace);
    ensureDir(dir);

    const baseName = module.name || "module";
    const safeName = baseName.replace(/[^a-zA-Z0-9_-]/g, "-");
    const filePath = path.join(dir, `${safeName}.md`);

    const markdown = renderModule(module);
    fs.writeFileSync(filePath, markdown, "utf-8");
  });

  console.log(
    `Generated Markdown for ${modules.length} module(s) in ${outputDir}`,
  );
}

main();
