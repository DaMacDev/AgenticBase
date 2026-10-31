// Leak check for this repo's CI. Flags absolute local paths and personal email addresses in tracked files and
// their names, and secrets anywhere in git history (gitleaks, pinned and hash-checked). Prints `file:line rule`,
// never the matched text. Exit 1 = findings, 2 = the check could not run.
// Reviewed exceptions live in .github/leak-allow.json as {rule, file, lineSha256} entries.
//   node .github/scripts/leak-check.mjs [--allow <leak-allow.json>]
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const sha256 = (b) => createHash("sha256").update(b).digest("hex");

export const ABS_PATH = [
  /(?<![A-Za-z0-9])[A-Za-z]:[\\/]/,
  /(?<![\w.~])\/{1,2}[A-Za-z]\/(?=[\w.])/,
  /(?<![\w.])\/(?:Users|home)\/[^/\s{]/,
  /(?<![\w.\\])\\\\[\w.$-]+\\/,
  /(?<![\w.])\/mnt\/[A-Za-z]\//,
];
export const EMAIL = /[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})/g;
export const GITLEAKS = {
  version: "8.30.1",
  asset: "gitleaks_8.30.1_linux_x64.tar.gz",
  sha256: "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb",
  binSha256: "88f91962aa2f93ac6ab281d553b9e125f5197bbbce38f9f2437f7299c32e5509",
};

const hasEmail = (line) => [...line.matchAll(EMAIL)].some((m) => !/(^|\.)noreply\.github\.com$/i.test(m[1]));
const ZERO_WIDTH = /[​-‏⁠﻿­]/g;
// Each line is also checked NFKC-folded and URL-decoded twice, so look-alike and %-encoded forms can't hide.
function forms(line) {
  let cur = line.normalize("NFKC").replace(ZERO_WIDTH, "");
  const out = new Set([line, cur]);
  for (let i = 0; i < 2; i++) {
    try { cur = decodeURIComponent(cur); } catch { cur = cur.replace(/%([0-9a-f]{2})/gi, (_m, h) => String.fromCharCode(parseInt(h, 16))); }
    out.add(cur);
  }
  return [...out];
}

function rulesFor(line) {
  const rules = new Set();
  for (const f of forms(line)) {
    if (ABS_PATH.some((r) => r.test(f))) rules.add("abs-path");
    if (hasEmail(f)) rules.add("email");
  }
  return [...rules];
}

/**
 * Findings for the given repo-relative files under `dir`, minus the allowed ones. A symlink or a binary file
 * (NUL byte; its lineSha256 is the hash of the whole file) is a finding of its own: its text isn't scanned.
 */
export function scanFiles(dir, files, allow = {}) {
  const ok = new Set((allow.allow ?? []).map((a) => `${a.rule}\0${a.file}\0${a.lineSha256}`));
  const found = [];
  const report = (file, lineNo, rule, hash) => { if (!ok.has(`${rule}\0${file}\0${hash}`)) found.push(`${file}:${lineNo} ${rule}`); };
  const check = (file, lineNo, line) => { for (const rule of rulesFor(line)) report(file, lineNo, rule, sha256(line)); };
  for (const file of files) {
    check(file, 0, file);
    if (lstatSync(path.join(dir, file)).isSymbolicLink()) { report(file, 0, "symlink", sha256(file)); continue; }
    const buf = readFileSync(path.join(dir, file));
    if (buf.includes(0)) { report(file, 0, "binary-file", sha256(buf)); continue; }
    buf.toString("utf8").split(/\r\n|\r|\n/).forEach((l, i) => check(file, i + 1, l));
  }
  return found;
}

export function loadAllow(file) {
  if (!existsSync(file)) return {};
  const j = JSON.parse(readFileSync(file, "utf8"));
  for (const a of j.allow ?? []) {
    if (!a.rule || !a.file || !/^[0-9a-f]{64}$/.test(a.lineSha256 ?? "")) throw new Error("leak-allow.json entry malformed");
  }
  return j;
}

async function gitleaksBin() {
  if (`${process.platform}-${process.arch}` !== "linux-x64") throw new Error("the pinned gitleaks is linux-x64 only");
  const dir = path.join(os.tmpdir(), `gitleaks-${GITLEAKS.version}`);
  const bin = path.join(dir, "gitleaks");
  if (!existsSync(bin)) {
    const r = await fetch(`https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS.version}/${GITLEAKS.asset}`);
    if (!r.ok) throw new Error("gitleaks download failed");
    const buf = Buffer.from(await r.arrayBuffer());
    if (sha256(buf) !== GITLEAKS.sha256) throw new Error("gitleaks download hash mismatch");
    mkdirSync(dir, { recursive: true });
    const archive = path.join(dir, GITLEAKS.asset);
    writeFileSync(archive, buf);
    execFileSync("tar", ["-xzf", archive, "-C", dir], { stdio: "ignore" });
    rmSync(archive, { force: true });
  }
  if (sha256(readFileSync(bin)) !== GITLEAKS.binSha256) throw new Error("gitleaks executable hash mismatch");
  chmodSync(bin, 0o755);
  return bin;
}

/** Secrets in the whole git history, with gitleaks' default rules only: no repo config, ignore file or inline allow. */
async function gitleaksHistory(repo) {
  const bin = await gitleaksBin();
  const tmp = mkdtempSync(path.join(os.tmpdir(), "lc-"));
  try {
    const cfg = path.join(tmp, "gitleaks.toml");
    const empty = path.join(tmp, "empty");
    const report = path.join(tmp, "r.json");
    writeFileSync(cfg, "[extend]\nuseDefault = true\n");
    mkdirSync(empty);
    const env = { ...process.env };
    delete env.GITLEAKS_CONFIG;
    delete env.GITLEAKS_CONFIG_TOML;
    // --text and no diff drivers: a `* -diff` line in .gitattributes would otherwise hide every patch.
    const logOpts = "--all --full-history --text --no-textconv --no-ext-diff";
    const args = ["git", repo, "--config", cfg, "--gitleaks-ignore-path", empty, "--ignore-gitleaks-allow", "--redact", "--no-banner", "--log-level", "error", "--exit-code", "1", "--report-format", "json", "--report-path", report, "--log-opts", logOpts];
    try { execFileSync(bin, args, { stdio: "ignore", env, cwd: tmp }); } catch (e) { if (e.status !== 1) throw new Error("gitleaks failed to run"); }
    const rows = JSON.parse(readFileSync(report, "utf8"));
    if (!Array.isArray(rows)) throw new Error("gitleaks report malformed");
    return rows.map((r) => `${r.File}:${r.StartLine} gitleaks:${r.RuleID} (commit ${String(r.Commit).slice(0, 7)})`);
  } finally { rmSync(tmp, { recursive: true, force: true }); }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const repo = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
    const files = execFileSync("git", ["-C", repo, "ls-files", "-z"], { encoding: "utf8" }).split("\0").filter(Boolean);
    const ai = process.argv.indexOf("--allow");
    const allowFile = ai > 0 ? path.resolve(process.argv[ai + 1]) : path.join(repo, ".github/leak-allow.json");
    const found = [...scanFiles(repo, files, loadAllow(allowFile)), ...(await gitleaksHistory(repo))];
    if (found.length) { console.error(found.join("\n")); process.exit(1); }
    console.log(`leak-check: ${files.length} files and the git history are clean`);
  } catch (e) {
    console.error(`leak-check: ${e.message}`);
    process.exit(2);
  }
}
