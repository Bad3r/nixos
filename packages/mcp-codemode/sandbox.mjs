// Copyright (c) 2026 Bad3r
//
// Isolated Code Mode script runner executed inside Node 24 (--permission) +
// Bubblewrap (--unshare-all). Communicates with the host gateway strictly over
// newline-delimited JSON on stdin/stdout; model code runs in a separate VM
// context without process, require, fetch, or filesystem globals.

import { stripTypeScriptTypes } from "node:module";
import readline from "node:readline";
import vm from "node:vm";

const MAX_LOG_LINES = 200;
const logs = [];
const pending = new Map();
let nextRpcId = 1;

function sendHost(msg) {
	process.stdout.write(`${JSON.stringify(msg)}\n`);
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
		return JSON.stringify(arg);
	} catch {
		return String(arg);
	}
}

function appendLog(level, args) {
	if (logs.length >= MAX_LOG_LINES) return;
	const prefix = level === "log" ? "" : `[${level}] `;
	logs.push(`${prefix}${args.map(formatLogArg).join(" ")}`);
}

function buildCodemode(mode, serverAliases) {
	const base = {
		servers: () => rpcCall("servers"),
		tools: (server, options) =>
			rpcCall("tools", {
				...(server ? { server: String(server) } : {}),
				...(options && typeof options === "object" ? options : {}),
			}),
		spec: (server, options) =>
			rpcCall("spec", {
				...(server ? { server: String(server) } : {}),
				...(options && typeof options === "object" ? options : {}),
			}),
	};

	if (mode !== "execute") {
		return Object.freeze(base);
	}

	const serverCache = new Map();
	const makeServerProxy = (serverKey) => {
		const canonical = serverAliases[serverKey] ?? serverKey;
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
				server: serverAliases[String(server)] ?? String(server),
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
	const cleaned = stripTypesIfPossible(source).trim();
	try {
		const expr = vm.runInContext(`(${cleaned})`, context);
		if (typeof expr === "function") {
			return expr;
		}
		return async () => expr;
	} catch {
		return vm.runInContext(`(async () => {\n${cleaned}\n})`, context);
	}
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

async function runCode(msg) {
	try {
		const codemode = buildCodemode(msg.mode, msg.serverAliases || {});
		const context = makeSandboxContext(codemode);
		const fn = compileUserCode(String(msg.code || ""), context);
		const value = await fn();
		sendHost({ type: "done", value: value === undefined ? null : value, logs });
	} catch (err) {
		const message = err instanceof Error ? err.message : String(err);
		sendHost({ type: "error", error: message, logs });
	} finally {
		process.exit(0);
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
