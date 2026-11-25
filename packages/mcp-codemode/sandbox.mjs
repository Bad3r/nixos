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
const objectGetPrototypeOf = Object.getPrototypeOf;
const objectGetOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
const arrayIsArray = Array.isArray;
const objectKeys = Object.keys;
const objectGetOwnPropertySymbols = Object.getOwnPropertySymbols;
const numberIsFinite = Number.isFinite;
const HostSet = Set;
const setHas = Function.prototype.call.bind(Set.prototype.has);
const setAdd = Function.prototype.call.bind(Set.prototype.add);
const setDelete = Function.prototype.call.bind(Set.prototype.delete);
const symbolToString = Function.prototype.call.bind(Symbol.prototype.toString);
const regexpTest = Function.prototype.call.bind(RegExp.prototype.test);
const identifierKey = /^[A-Za-z_$][\w$]*$/;
const arrayIndexKey = /^(?:0|[1-9]\d*)$/;
const hostObjectPrototype = Object.prototype;
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
let vmObjectPrototype = hostObjectPrototype;

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

// Names a rejected value's kind without invoking user getters.
function describeArgsKind(value) {
	if (value === null) return "null";
	if (typeof value === "number") {
		return numberIsFinite(value) ? "number" : "non-finite number";
	}
	if (typeof value !== "object") return typeof value;
	if (arrayIsArray(value)) return "array";
	const proto = objectGetPrototypeOf(value);
	if (proto === null) return "object";
	const ctor = objectGetOwnPropertyDescriptor(proto, "constructor")?.value;
	const name =
		typeof ctor === "function"
			? objectGetOwnPropertyDescriptor(ctor, "name")?.value
			: undefined;
	return typeof name === "string" && name
		? `${name} instance`
		: "non-plain object";
}

function isPlainObject(value) {
	if (value === null || typeof value !== "object" || arrayIsArray(value)) {
		return false;
	}
	const proto = objectGetPrototypeOf(value);
	return (
		proto === null ||
		proto === vmObjectPrototype ||
		proto === hostObjectPrototype
	);
}

function childPath(path, key) {
	if (typeof key === "number") return `${path}[${key}]`;
	return regexpTest(identifierKey, key)
		? `${path}.${key}`
		: `${path}[${safeJsonStringify(key)}]`;
}

// Copies in one pass so getters and proxies cannot change what was checked.
// Undefined object properties are dropped, as JSON does.
function copyPlainJson(value, path, ancestors, fail) {
	if (
		value === null ||
		typeof value === "string" ||
		typeof value === "boolean" ||
		(typeof value === "number" && numberIsFinite(value))
	) {
		return value;
	}
	if (
		typeof value !== "object" ||
		!(arrayIsArray(value) || isPlainObject(value))
	) {
		fail(path, describeArgsKind(value));
	}
	if (setHas(ancestors, value)) fail(path, "circular reference");
	setAdd(ancestors, value);
	for (const sym of objectGetOwnPropertySymbols(value)) {
		if (objectGetOwnPropertyDescriptor(value, sym)?.enumerable) {
			fail(`${path}[${symbolToString(sym)}]`, "symbol key");
		}
	}
	let out;
	if (arrayIsArray(value)) {
		out = [];
		const length = value.length;
		for (const key of objectKeys(value)) {
			if (!regexpTest(arrayIndexKey, key) || +key >= length) {
				fail(childPath(path, key), "non-index array key");
			}
		}
		for (let i = 0; i < length; i++) {
			if (!objectHasOwn(value, i)) fail(childPath(path, i), "hole");
			const item = value[i];
			if (item === undefined) fail(childPath(path, i), "undefined");
			out[i] = copyPlainJson(item, childPath(path, i), ancestors, fail);
		}
	} else {
		out = objectCreate(null);
		for (const key of objectKeys(value)) {
			const item = value[key];
			if (item === undefined) continue;
			out[key] = copyPlainJson(item, childPath(path, key), ancestors, fail);
		}
	}
	setDelete(ancestors, value);
	return out;
}

// JSON.stringify drops functions and Symbols and turns Map or Set into {}.
function callTool(server, tool, args) {
	let copy;
	let failed = false;
	try {
		const fail = (path, kind, expected = "plain JSON") => {
			const err = vmMakeError(
				`${server}.${tool}: ${path} must be ${expected}, got ${kind}`,
			);
			failed = true;
			throw err;
		};
		if (!isPlainObject(args)) {
			fail("args", describeArgsKind(args), "a plain object");
		}
		copy = copyPlainJson(args, "args", new HostSet(), fail);
	} catch (err) {
		// Getters, proxies, and stack overflow throw without the tool name.
		const detail = safeErrorMessage(err);
		return HostPromise.reject(
			vmMakeError(
				failed
					? detail
					: `${server}.${tool}: args could not be read: ${detail}`,
			),
		);
	}
	return rpcCall("call_tool", { server, tool, args: copy });
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
				return (args = {}) => callTool(canonical, toolProp, args);
			},
		});
		serverCache[canonical] = proxy;
		return proxy;
	};

	const execBase = {
		...base,
		call: (server, tool, args = {}) =>
			callTool(
				resolveCanonicalServer(serverAliases, String(server)),
				String(tool),
				args,
			),
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
	vmObjectPrototype = vm.runInContext("Object.prototype", context);
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
