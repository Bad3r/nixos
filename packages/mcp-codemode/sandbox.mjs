// Copyright (c) 2026 Bad3r
//
// Isolated Code Mode script runner executed inside Node 24 (--permission,
// --disallow-code-generation-from-strings, --disable-proto=throw) + Bubblewrap
// (--unshare-all --cap-drop ALL) for OS/filesystem/network/codegen confinement.
// Model code runs in a separate node:vm context without process, require, fetch,
// or filesystem globals and communicates with the host gateway strictly over
// newline-delimited JSON on stdin/stdout.

import { stripTypeScriptTypes } from "node:module";
import readline from "node:readline";
import vm from "node:vm";

// Capture primordials before user code executes so host IPC cannot be hooked.
const objectAssign = Object.assign;
const objectCreate = Object.create;
const objectFreeze = Object.freeze;
const objectHasOwn = Object.hasOwn;
const reflectGet = Reflect.get;
const HostPromise = Promise;
const safeJsonParse = JSON.parse;
const safeJsonStringify = JSON.stringify;
const isError = Error.isError;
const hostSetTimeout = setTimeout;
const hostClearTimeout = clearTimeout;
const stringTrim = Function.prototype.call.bind(String.prototype.trim);
const stringSlice = Function.prototype.call.bind(String.prototype.slice);

const MAX_LOG_LINES = 200;
const MAX_LOG_BYTES = 64 * 1024;
const logs = [];
let logBytes = 0;
const pending = objectCreate(null);
const timers = objectCreate(null);
let nextRpcId = 1;
let nextTimerId = 1;
let started = false;
let finished = false;
let vmJsonParse = (raw) => safeJsonParse(raw);
let vmMakeError = (message) => new Error(message);

// Seal reachable host constructors and prototypes before user code runs.
for (const ctor of [
	Object,
	Array,
	Function,
	Promise,
	Error,
	TypeError,
	RangeError,
	SyntaxError,
	ReferenceError,
	URIError,
	EvalError,
	String,
	Number,
	Boolean,
	BigInt,
	Symbol,
	URL,
	URLSearchParams,
	TextEncoder,
	TextDecoder,
	Map,
	Set,
	Date,
	RegExp,
	ArrayBuffer,
	DataView,
	Uint8Array,
]) {
	objectFreeze(ctor);
}
for (const proto of [
	Object.prototype,
	Array.prototype,
	Function.prototype,
	Promise.prototype,
	String.prototype,
	Number.prototype,
	Boolean.prototype,
	BigInt.prototype,
	Symbol.prototype,
	URL.prototype,
	URLSearchParams.prototype,
	TextEncoder.prototype,
	TextDecoder.prototype,
	Map.prototype,
	Set.prototype,
	Date.prototype,
	RegExp.prototype,
	ArrayBuffer.prototype,
	DataView.prototype,
	Uint8Array.prototype,
	Object.getPrototypeOf(Uint8Array.prototype),
]) {
	objectFreeze(proto);
}
for (const errProto of [
	Error.prototype,
	TypeError.prototype,
	RangeError.prototype,
	SyntaxError.prototype,
	ReferenceError.prototype,
	URIError.prototype,
	EvalError.prototype,
]) {
	Object.preventExtensions(errProto);
}

function safeErrorMessage(err) {
	if (isError(err)) {
		try {
			return String(err.message);
		} catch {
			return "Error";
		}
	}
	try {
		return String(err);
	} catch {
		return "[unprintable error]";
	}
}

function serializeTerminalEnvelope(msg) {
	const envelope = objectAssign(objectCreate(null), msg);
	try {
		return safeJsonStringify(envelope);
	} catch (err) {
		const fallback = objectAssign(objectCreate(null), {
			type: "error",
			error: `sandbox result serialization failed: ${safeErrorMessage(err)}`,
			logs,
		});
		return safeJsonStringify(fallback);
	}
}

function sendHostAndWait(msg) {
	return new HostPromise((resolve, reject) => {
		process.stdout.write(`${serializeTerminalEnvelope(msg)}\n`, (err) => {
			if (err) {
				reject(err);
			} else {
				resolve();
			}
		});
	});
}

function rpcCall(method, params = {}) {
	return new HostPromise((resolve, reject) => {
		const id = nextRpcId++;
		let wire;
		try {
			wire = safeJsonStringify(
				objectAssign(objectCreate(null), {
					type: "rpc",
					id,
					method,
					params,
				}),
			);
		} catch (err) {
			reject(
				vmMakeError(
					`RPC argument serialization failed: ${safeErrorMessage(err)}`,
				),
			);
			return;
		}
		pending[id] = { resolve, reject };
		process.stdout.write(`${wire}\n`);
	});
}

function formatLogArg(arg) {
	if (typeof arg === "string") return arg;
	if (arg === undefined) return "undefined";
	if (typeof arg === "function") {
		return `[Function: ${arg.name || "anonymous"}]`;
	}
	try {
		const serialized = safeJsonStringify(arg);
		if (serialized !== undefined) return serialized;
	} catch {
		// Fall through to safe stringification.
	}
	try {
		return String(arg);
	} catch {
		return "[unprintable value]";
	}
}

function appendLog(level, args) {
	if (logs.length >= MAX_LOG_LINES || logBytes >= MAX_LOG_BYTES) return;
	const prefix = level === "log" ? "" : `[${level}] `;
	let line = `${prefix}${args.map(formatLogArg).join(" ")}`;
	const remaining = MAX_LOG_BYTES - logBytes;
	if (line.length > remaining) {
		line = `${stringSlice(line, 0, Math.max(0, remaining - 3))}...`;
	}
	logBytes += line.length;
	logs.push(line);
}

function normalizeDiscoveryParams(server, options) {
	if (server && typeof server === "object") {
		return { ...server };
	}
	return {
		...(server ? { server: String(server) } : {}),
		...(options && typeof options === "object" ? options : {}),
	};
}

function resolveCanonicalServer(serverAliases, key) {
	return objectHasOwn(serverAliases, key) ? serverAliases[key] : key;
}

function buildCodemode(mode, serverAliases) {
	const base = {
		servers: () => rpcCall("servers"),
		tools: (server, options) =>
			rpcCall("tools", normalizeDiscoveryParams(server, options)),
		spec: (server, options) =>
			rpcCall("spec", normalizeDiscoveryParams(server, options)),
	};

	if (mode !== "execute") {
		return objectFreeze(base);
	}

	const serverCache = objectCreate(null);
	const makeServerProxy = (serverKey) => {
		const canonical = resolveCanonicalServer(serverAliases, serverKey);
		if (objectHasOwn(serverCache, canonical)) return serverCache[canonical];
		const proxy = new Proxy(objectCreate(null), {
			get(_target, toolProp) {
				if (
					typeof toolProp !== "string" ||
					toolProp === "then" ||
					toolProp === "toJSON"
				) {
					return undefined;
				}
				return (args = {}) =>
					rpcCall("call_tool", {
						server: canonical,
						tool: toolProp,
						args: args ?? {},
					});
			},
		});
		serverCache[canonical] = proxy;
		return proxy;
	};

	const execBase = {
		...base,
		call: (server, tool, args = {}) =>
			rpcCall("call_tool", {
				server: resolveCanonicalServer(serverAliases, String(server)),
				tool: String(tool),
				args: args ?? {},
			}),
	};

	return new Proxy(execBase, {
		get(target, prop, receiver) {
			if (typeof prop !== "string") return undefined;
			if (objectHasOwn(target, prop)) {
				return reflectGet(target, prop, receiver);
			}
			if (prop === "then" || prop === "toJSON") return undefined;
			return makeServerProxy(prop);
		},
	});
}

function stripTypesIfPossible(source) {
	try {
		return stripTypeScriptTypes(source);
	} catch {
		return source;
	}
}

function stripTrailingSemicolonAndComments(source) {
	let current = stringTrim(source);
	while (true) {
		const next = stringTrim(
			current
				.replace(/(?:^|\n)[ \t]*\/\/[^\n]*$/, "")
				.replace(/\/\*(?:[^*]|\*(?!\/))*\*\/\s*$/, "")
				.replace(/;\s*$/, ""),
		);
		if (next === current) return current;
		current = next;
	}
}

function tryCompileExpr(candidate) {
	if (!candidate) return null;
	const wrappedExpr = stripTypesIfPossible(`(async () => (\n${candidate}\n))`);
	try {
		return new vm.Script(wrappedExpr);
	} catch {
		return null;
	}
}

function compileUserCode(source, context) {
	const trimmed = stringTrim(source);
	// Pre-strip top-level TypeScript declarations (e.g. `type X = ...; async () => ...`)
	// before testing single-expression wrapping.
	const preStripped = stringTrim(stripTypesIfPossible(trimmed));
	let exprScript = tryCompileExpr(preStripped);
	if (exprScript === null) {
		const exprCandidate = stripTrailingSemicolonAndComments(preStripped);
		exprScript = tryCompileExpr(exprCandidate);
		if (exprScript === null && /;\s*\/\/[^\n]*$/.test(exprCandidate)) {
			exprScript = tryCompileExpr(
				stringTrim(exprCandidate.replace(/;(\s*\/\/[^\n]*)$/, "$1")),
			);
		}
	}
	if (exprScript !== null) {
		const outer = exprScript.runInContext(context);
		return async () => {
			const value = await outer();
			return typeof value === "function" ? await value() : value;
		};
	}
	const wrappedBody = stripTypesIfPossible(`(async () => {\n${trimmed}\n})`);
	const bodyScript = new vm.Script(wrappedBody);
	return bodyScript.runInContext(context);
}

function sandboxSetTimeout(fn, delay, ...args) {
	const id = nextTimerId++;
	const handle = hostSetTimeout(() => {
		delete timers[id];
		if (typeof fn === "function") fn(...args);
	}, delay);
	timers[id] = handle;
	return id;
}

function sandboxClearTimeout(id) {
	if (typeof id === "number" && objectHasOwn(timers, id)) {
		hostClearTimeout(timers[id]);
		delete timers[id];
	}
}

function makeSandboxContext(codemode) {
	const safeConsole = objectFreeze({
		log: (...args) => appendLog("log", args),
		info: (...args) => appendLog("info", args),
		warn: (...args) => appendLog("warn", args),
		error: (...args) => appendLog("error", args),
	});
	const sandbox = {
		codemode,
		console: safeConsole,
		URL,
		URLSearchParams,
		TextEncoder,
		TextDecoder,
		structuredClone,
		atob,
		btoa,
		setTimeout: sandboxSetTimeout,
		clearTimeout: sandboxClearTimeout,
	};
	const context = vm.createContext(sandbox, {
		codeGeneration: { strings: false, wasm: false },
	});
	vmJsonParse = vm.runInContext(
		"(() => { const parse = JSON.parse; return (s) => parse(s); })()",
		context,
	);
	vmMakeError = vm.runInContext(
		"(() => { const Err = Error; return (m) => new Err(m); })()",
		context,
	);
	return context;
}

async function finishWith(msg) {
	if (finished) return;
	finished = true;
	for (const id of Object.keys(timers)) {
		hostClearTimeout(timers[id]);
		delete timers[id];
	}
	try {
		await sendHostAndWait(msg);
	} finally {
		rl.close();
		process.exit(0);
	}
}

process.on("uncaughtException", (err) => {
	void finishWith({ type: "error", error: safeErrorMessage(err), logs });
});

process.on("unhandledRejection", (reason) => {
	void finishWith({ type: "error", error: safeErrorMessage(reason), logs });
});

async function runCode(msg) {
	try {
		const codemode = buildCodemode(msg.mode, msg.serverAliases || {});
		const context = makeSandboxContext(codemode);
		const fn = compileUserCode(String(msg.code || ""), context);
		const value = await fn();
		await finishWith({
			type: "done",
			value: value === undefined ? null : value,
			logs,
		});
	} catch (err) {
		await finishWith({ type: "error", error: safeErrorMessage(err), logs });
	}
}

const rl = readline.createInterface({
	input: process.stdin,
	crlfDelay: Infinity,
});
rl.on("line", (line) => {
	const trimmed = stringTrim(line);
	if (!trimmed) return;
	let msg;
	try {
		msg = safeJsonParse(trimmed);
	} catch {
		return;
	}
	if (msg.type === "run") {
		if (started) return;
		started = true;
		void runCode(msg);
	} else if (msg.type === "rpc_result") {
		if (!objectHasOwn(pending, msg.id)) return;
		const waiter = pending[msg.id];
		delete pending[msg.id];
		if (msg.ok) {
			try {
				const marshalled =
					msg.result === undefined
						? undefined
						: vmJsonParse(safeJsonStringify(msg.result));
				waiter.resolve(marshalled);
			} catch (err) {
				waiter.reject(vmMakeError(safeErrorMessage(err)));
			}
		} else {
			waiter.reject(vmMakeError(String(msg.error || "upstream RPC failed")));
		}
	}
});
