#!/usr/bin/env bun
// Releases BudgieMac from this Mac: checks, version bump, tests, build, zip,
// then a tag on main and a GitHub Release with the zip attached.
//
// Usage: bun run release [major|minor|patch] [--dry-run]
//   With no level it recommends one from the commits since the last tag and asks.
//   --dry-run does everything up to the zip, then puts the version files back:
//   nothing is committed, tagged, pushed or published.
import { $ } from "bun";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

type Level = "major" | "minor" | "patch";
const levels: Level[] = ["patch", "minor", "major"];

const root = join(import.meta.dir, "..");
$.cwd(root);
const plistPath = join(root, "Info.plist.in");
const changelogPath = join(root, "CHANGELOG.md");
const versionPattern = /(<key>CFBundleShortVersionString<\/key><string>)([^<]+)(<\/string>)/;

const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) {
  console.log("Usage: bun run release [major|minor|patch] [--dry-run]");
  process.exit(0);
}
const dryRun = args.includes("--dry-run");
const levelArg = args.find((a) => !a.startsWith("-"));
if (levelArg && !levels.includes(levelArg as Level)) fail(`Unknown level "${levelArg}": use major, minor or patch.`);

// The SwiftUI and SwiftData macro plugins ship with Xcode, not the Command Line Tools.
if (!process.env.DEVELOPER_DIR && (await $`xcode-select -p`.text()).trim().endsWith("CommandLineTools")
    && existsSync("/Applications/Xcode.app")) {
  process.env.DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";
}

// 1. Preflight: a clean main, level with origin, and gh signed in.
step("Checking the repository");
const branch = (await $`git branch --show-current`.text()).trim();
if (branch !== "main") fail(`Releases come from main; this is ${branch || "a detached HEAD"}.`);
if ((await $`git status --porcelain`.text()).trim()) fail("The working tree has changes. Commit or stash them first.");
await $`git fetch --quiet --tags origin main`;
const [head, remote] = await Promise.all([$`git rev-parse HEAD`.text(), $`git rev-parse origin/main`.text()]);
if (head.trim() !== remote.trim()) fail("main is not level with origin/main. Pull or push first.");
if ((await $`gh auth status`.nothrow().quiet()).exitCode !== 0) fail("gh is not signed in. Run: gh auth login");

// 2. Pick the version.
const plist = readFileSync(plistPath, "utf8");
const current = plist.match(versionPattern)?.[2];
if (!current || !parse(current)) fail(`Info.plist.in has no x.y.z version (found "${current}").`);
const tags = (await $`git tag --list ${"v*"}`.text()).split("\n").filter(Boolean);
const lastTag = tags.filter((t) => parse(t.slice(1))).sort((a, b) => compare(a.slice(1), b.slice(1))).at(-1);
const range = lastTag ? `${lastTag}..HEAD` : "HEAD";
const subjects = (await $`git log --format=%s ${range}`.text())
  .split("\n").filter((s) => s && !/^Release \d+\.\d+\.\d+$/.test(s));
const currentUnreleased = !tags.includes(`v${current}`);
if (!subjects.length && !currentUnreleased) fail(`Nothing to release: no commits since ${lastTag}.`);

let next: string;
if (levelArg) {
  next = bump(current, levelArg as Level);
} else {
  console.log(`\nCurrent version ${current}${lastTag ? `, last released ${lastTag}` : ", never released"}.`);
  console.log(`${subjects.length} commit${subjects.length === 1 ? "" : "s"} since ${lastTag ?? "the start"}:`);
  for (const s of subjects.slice(0, 15)) console.log(`  - ${s}`);
  if (subjects.length > 15) console.log(`  … and ${subjects.length - 15} more`);
  const options: { label: string; version: string }[] = [];
  if (currentUnreleased) options.push({ label: "as is", version: current });
  for (const level of levels) options.push({ label: level, version: bump(current, level) });
  const recommended = currentUnreleased ? 0 : options.findIndex((o) => o.label === recommend(subjects));
  console.log("");
  options.forEach((o, i) => console.log(`  ${i + 1}) ${o.label.padEnd(6)} → ${o.version}${i === recommended ? "  (recommended)" : ""}`));
  const answer = (prompt(`Which version? [${recommended + 1}]`) ?? "").trim();
  const picked = answer === "" ? recommended : Number(answer) - 1;
  if (!options[picked]) fail(`No option "${answer}".`);
  next = options[picked].version;
}
if (tags.includes(`v${next}`) || (await $`git ls-remote --tags origin v${next}`.text()).trim()) fail(`v${next} already exists.`);
if (compare(next, current) < 0) fail(`${next} is lower than the current ${current}.`);

// 3. Release notes: the changelog's section for this version, or a draft from the commits.
const changelog = readFileSync(changelogPath, "utf8");
let notes = section(changelog, next) ?? subjects.map((s) => `- ${s}`).join("\n");
const hasSection = section(changelog, next) !== undefined;
for (;;) {
  console.log(`\nRelease notes for ${next}${hasSection ? " (from CHANGELOG.md)" : " (drafted from commits, added to CHANGELOG.md)"}:\n`);
  console.log(notes.replace(/^/gm, "  "));
  const answer = (prompt("\nUse these notes? [Y]es, [e]dit, [n]o") ?? "").trim().toLowerCase();
  if (answer === "" || answer === "y" || answer === "yes") break;
  if (answer === "n" || answer === "no") fail("Stopped. Nothing was changed.");
  if (answer === "e" || answer === "edit") notes = await edit(notes);
}

const verb = dryRun ? "Dry run: test, build and zip" : "Test, build, commit, tag, push and publish";
if (!/^y(es)?$/i.test((prompt(`\n${verb} v${next}? [y/N]`) ?? "").trim())) fail("Stopped. Nothing was changed.");

// 4. Write the version and notes; put them back if anything fails before the commit.
const newChangelog = changelog.replace(new RegExp(`^## ${escape(next)}\\s*\\n[\\s\\S]*?(?=^## |$(?![\\s\\S]))`, "m"), "")
  .replace(/^(# .*\n+)/, (title) => `${title}## ${next}\n\n${notes.trim()}\n\n`);
writeFileSync(plistPath, plist.replace(versionPattern, `$1${next}$3`));
writeFileSync(changelogPath, hasSection && notes === section(changelog, next) ? changelog : newChangelog);
const changed = (await $`git status --porcelain`.text()).trim() !== "";
let committed = false;
const restore = () => { if (!committed) { writeFileSync(plistPath, plist); writeFileSync(changelogPath, changelog); } };
process.on("exit", restore);

const stage = join(homedir(), "Library/Developer/BudgieMac/release", next);
const zip = join(stage, `BudgieMac-${next}.zip`);
try {
  step("Unit tests");
  await $`swift test --scratch-path ${join(homedir(), "Library/Developer/BudgieMac/test-build")}`.quiet();
  step("Grid lint");
  await $`tools/grid-lint.sh`;

  step(`Building ${next}`);
  rmSync(stage, { recursive: true, force: true });
  mkdirSync(stage, { recursive: true });
  // The build number is the commit count, counting the release commit about to be made.
  const count = Number((await $`git rev-list --count HEAD`.text()).trim()) + (changed ? 1 : 0);
  await $`./build.sh --out ${stage}`.env({ ...process.env, BUILD_NUMBER: String(count) });
  const app = join(stage, "BudgieMac.app");
  const built = (await $`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ${join(app, "Contents/Info.plist")}`.text()).trim();
  if (built !== next) fail(`The built app says ${built}, not ${next}.`);

  step("Self-test on the built app");
  await $`tools/selftest.sh ${app}`.quiet();

  step("Packaging");
  // ditto keeps the signature and extended attributes intact; zip does not.
  await $`ditto -c -k --keepParent ${app} ${zip}`;
  await $`shasum -a 256 BudgieMac-${next}.zip > BudgieMac-${next}.zip.sha256`.cwd(stage);
} catch (error) {
  // The lines that say what failed, or the end of the output when none do.
  const lines = error instanceof $.ShellError ? `${error.stdout}\n${error.stderr}`.trim().split("\n") : [String(error)];
  const failures = lines.filter((l) => /✘|error:|FAIL/.test(l));
  const output = (failures.length ? failures : lines).slice(-40).join("\n");
  fail(`${output}\nNothing was committed or published.`);
}

if (dryRun) {
  console.log(`\nDry run done: ${zip}\nThe version files are back as they were. Nothing was committed, tagged or published.`);
  process.exit(0);
}

// 5. Commit, tag and push together, then publish the release.
step(`Tagging v${next}`);
if (changed) {
  await $`git commit --quiet -m ${`Release ${next}`} -- Info.plist.in CHANGELOG.md`;
}
committed = true;
await $`git tag -a v${next} -m ${`BudgieMac ${next}`}`;
if ((await $`git push --quiet --atomic origin main v${next}`.nothrow()).exitCode !== 0) {
  fail(`The release commit and tag v${next} are made here but not pushed. Fix the push, then run:
  git push --atomic origin main v${next}`);
}

step("Publishing the GitHub release");
const notesFile = join(stage, "notes.md");
writeFileSync(notesFile, `${notes.trim()}

### Install

Unzip, then move BudgieMac.app to Applications. It needs macOS 26 or later.
The app is not notarised, so macOS may say it is damaged. If so, run:

\`\`\`bash
xattr -d com.apple.quarantine /Applications/BudgieMac.app
\`\`\`
`);
const publish = await $`gh release create v${next} ${zip} ${zip}.sha256 --draft --verify-tag --title ${`BudgieMac ${next}`} --notes-file ${notesFile}`
  .nothrow();
if (publish.exitCode === 0) await $`gh release edit v${next} --draft=false`.nothrow();
if (publish.exitCode !== 0) {
  fail(`v${next} is tagged and pushed, but the release was not published. Retry with:
  gh release create v${next} ${zip} ${zip}.sha256 --verify-tag --title "BudgieMac ${next}" --notes-file ${notesFile}`);
}
console.log(`\nReleased v${next}: ${(await $`gh release view v${next} --json url --jq .url`.text()).trim()}`);

// Helpers.

function parse(version: string): [number, number, number] | undefined {
  const m = version.match(/^(\d+)\.(\d+)\.(\d+)$/);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : undefined;
}

function compare(a: string, b: string): number {
  const [x, y] = [parse(a)!, parse(b)!];
  return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
}

function bump(version: string, level: Level): string {
  const [major, minor, patch] = parse(version)!;
  if (level === "major") return `${major + 1}.0.0`;
  if (level === "minor") return `${major}.${minor + 1}.0`;
  return `${major}.${minor}.${patch + 1}`;
}

/// Major when a commit says it breaks something, patch when every commit is a
/// fix or a tidy-up, minor otherwise (something new you can do).
function recommend(subjects: string[]): Level {
  if (subjects.some((s) => /\bbreaking\b|^\w+(\(.+\))?!:/i.test(s))) return "major";
  const small = /^(fix|fixes|fixed|keep|correct|tidy|refactor|docs?|readme|test|tests|chore|bump)\b/i;
  return subjects.length && subjects.every((s) => small.test(s)) ? "patch" : "minor";
}

function section(text: string, version: string): string | undefined {
  const m = text.match(new RegExp(`^## ${escape(version)}\\s*\\n([\\s\\S]*?)(?=^## |$(?![\\s\\S]))`, "m"));
  return m?.[1].trim();
}

function escape(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function edit(text: string): Promise<string> {
  const file = join(tmpdir(), `budgiemac-notes-${process.pid}.md`);
  writeFileSync(file, text);
  const editor = process.env.VISUAL || process.env.EDITOR || "vi";
  // The editor needs the terminal, so it runs outside Bun's shell.
  await Bun.spawn(["/bin/sh", "-c", `${editor} "$0"`, file], { stdio: ["inherit", "inherit", "inherit"] }).exited;
  const edited = readFileSync(file, "utf8").trim();
  rmSync(file, { force: true });
  return edited || text;
}

function step(text: string) {
  console.log(`\n▸ ${text}`);
}

function fail(text: string): never {
  console.error(`\n✗ ${text}`);
  process.exit(1);
}
