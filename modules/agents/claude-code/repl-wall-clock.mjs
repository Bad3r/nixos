// Rewrites the Code Mode REPL per-turn wall clock in a native Claude Code
// binary. The constant sits in the module that names "repl-tool-code.js",
// right after the script time limit, and has no setting or env var. Through
// tweakcc the edited module is repacked without its bytecode, so the binary
// runs the edited source.
// Usage: node repl-wall-clock.mjs <tweakcc nativeInstallation module> <binary> <output> <ms>
// Exit 0: patched copy written to <output>. Exit 3: already <ms>, nothing written.
import { pathToFileURL } from "node:url";

const [nativeModule, binary, output, msArg] = process.argv.slice(2);
const ms = Number(msArg);
if (!Number.isSafeInteger(ms) || ms <= 0)
	throw new Error(`invalid wall clock: ${msArg}`);

const {
	extractClaudeJsModulesFromNativeInstallation: extract,
	repackNativeInstallationModules: repack,
} = await import(pathToFileURL(nativeModule).href);

const pattern =
	/("repl-tool-code\.js",[\w$]+=\d+,)([\w$]+)=(\d+)(;function [\w$]+\(\)\{return \2\})/g;

const graph = extract(binary);
if (!graph) throw new Error(`cannot read the Bun module graph of ${binary}`);

const hits = [];
for (const module of graph.modules) {
	if (!module.isJavaScript) continue;
	const source = module.contents.toString("utf8");
	const matches = [...source.matchAll(pattern)];
	if (matches.length > 0) hits.push({ module, source, matches });
}
const total = hits.reduce((n, hit) => n + hit.matches.length, 0);
if (total !== 1)
	throw new Error(
		`expected one REPL wall clock constant, found ${total}; the Claude Code bundle changed`,
	);

const [
	{
		module,
		source,
		matches: [match],
	},
] = hits;
if (Number(match[3]) === ms) process.exit(3);

const patched = source.replace(
	pattern,
	(_, head, name, _old, tail) => `${head}${name}=${ms}${tail}`,
);
repack(
	binary,
	{
		sourceSha256: graph.sourceSha256,
		moduleStructSize: graph.moduleStructSize,
		entryPointId: graph.entryPointId,
		modules: [{ ...module, contents: Buffer.from(patched, "utf8") }],
	},
	output,
);
console.log(`REPL wall clock ${match[3]} -> ${ms} ms in ${module.name}`);
