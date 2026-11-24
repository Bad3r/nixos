// Copyright (c) 2026 Bad3r
//
// Isolated Code Mode script runner executed inside Node 24 (--permission,
// --disallow-code-generation-from-strings, --disable-proto=throw) + Bubblewrap
// (--unshare-all) for OS/filesystem/network/codegen confinement. Model code
// runs in a separate node:vm context without process, require, fetch, or
// filesystem globals and communicates with the host gateway strictly over
// newline-delimited JSON on stdin/stdout.

import { stripTypeScriptTypes } from "node:module";
import readline from "node:readline";
import vm from "node:vm";

const MAX_LOG_LINES = 200;
const MAX_LOG_BYTES = 64 * 1024;
const logs = [];
let logBytes = 0;
const pending = new Map();
let nextRpcId = 1;
let finished = false;

const safeJsonStringify = JSON.stringify;

// Seal host-realm prototypes reachable through bridged objects before user code runs.
for (const proto of [
	Object.prototype,
	Array.prototype,
	Function.prototype,
	Promise.prototype,
	URL.prototype,
	URLSearchParams.prototype,
	TextEncoder.prototype,
	TextDecoder.prototype,
]) {
	Object.freeze(proto);
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

function serializeEnvelope(msg) {
	const envelope = Object.assign(Object.create(null), msg);
	try {
		return safeJsonStringify(envelope);
	} catch (err) {
		const reason = err instanceof Error ? err.message : String(err);
		const fallback = Object.assign(Object.create(null), {
			type: "error",
			error: `sandbox result serialization failed: ${reason}`,
			logs,
		});
		return safeJsonStringify(fallback);
	}
}

function sendHost(msg) {
	process.stdout.write(`${serializeEnvelope(msg)}\n`);
}

function sendHostAndWait(msg) {
	return new Promise((resolve, reject) => {
		process.stdout.write(`${serializeEnvelope(msg)}\n`, (err) => {
			if (err) {
				reject(err);
			} else {
				resolve();
			}
		});
	});
}

function rpcCall(method, params = {}) {
	return new Promise((resolve, reject) => {
		const id = nextRpcId++;
		pending.set(id, { resolve, reject });
		sendHost({ type: "rpc", id, method, params });
	});
}

function formatLogArg(arg) {
	if (typeof arg === "string") return arg;
	try {
		return safeJsonStringify(arg);
	} catch {
		return String(arg);
	}
}

function appendLog(level, args) {
	if (logs.length >= MAX_LOG_LINES || logBytes >= MAX_LOG_BYTES) return;
	const prefix = level === "log" ? "" : `[${level}] `;
	let line = `${prefix}${args.map(formatLogArg).join(" ")}`;
	const remaining = MAX_LOG_BYTES - logBytes;
	if (line.length > remaining) {
		line = `${line.slice(0, Math.max(0, remaining - 3))}...`;
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
	return Object.hasOwn(serverAliases, key) ? serverAliases[key] : key;
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
		return Object.freeze(base);
	}

	const serverCache = new Map();
	const makeServerProxy = (serverKey) => {
		const canonical = resolveCanonicalServer(serverAliases, serverKey);
		if (serverCache.has(canonical)) return serverCache.get(canonical);
		const proxy = new Proxy(Object.create(null), {
			get(_target, toolProp) {
				if (typeof toolProp !== "string" || toolProp === "then") {
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
		serverCache.set(canonical, proxy);
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
			if (Object.hasOwn(target, prop)) {
				return Reflect.get(target, prop, receiver);
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

function compileUserCode(source, context) {
	const trimmed = source.trim();
	const exprCandidate = trimmed.replace(/;+\s*$/, "");
	let exprScript = null;
	if (exprCandidate) {
		const wrappedExpr = stripTypesIfPossible(
			`(async () => (\n${exprCandidate}\n))`,
		);
		try {
			exprScript = new vm.Script(wrappedExpr);
		} catch {
			exprScript = null;
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

function makeSandboxContext(codemode) {
	const safeConsole = Object.freeze({
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
		setTimeout,
		clearTimeout,
	};
	return vm.createContext(sandbox, {
		codeGeneration: { strings: false, wasm: false },
	});
}

async function finishWith(msg) {
	if (finished) return;
	finished = true;
	try {
		await sendHostAndWait(msg);
	} finally {
		rl.close();
		process.exit(0);
	}
}

process.on("uncaughtException", (err) => {
	const message = err instanceof Error ? err.message : String(err);
	void finishWith({ type: "error", error: message, logs });
});

process.on("unhandledRejection", (reason) => {
	const message = reason instanceof Error ? reason.message : String(reason);
	void finishWith({ type: "error", error: message, logs });
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
		const message = err instanceof Error ? err.message : String(err);
		await finishWith({ type: "error", error: message, logs });
	}
}

const rl = readline.createInterface({
	input: process.stdin,
	crlfDelay: Infinity,
});
rl.on("line", (line) => {
	const trimmed = line.trim();
	if (!trimmed) return;
	let msg;
	try {
		msg = JSON.parse(trimmed);
	} catch {
		return;
	}
	if (msg.type === "run") {
		void runCode(msg);
	} else if (msg.type === "rpc_result") {
		const waiter = pending.get(msg.id);
		if (!waiter) return;
		pending.delete(msg.id);
		if (msg.ok) {
			waiter.resolve(msg.result);
		} else {
			waiter.reject(new Error(String(msg.error || "upstream RPC failed")));
		}
	}
});
