import { createHash } from "node:crypto";
import { lstat, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve, relative, sep } from "node:path";

const manifestName = "hypha-room-template.json";
const allowed = new Set(["html", "css", "js", "mjs", "json", "wasm", "png", "jpg", "jpeg", "gif", "svg", "webp", "woff", "woff2", "txt"]);
const textual = new Set(["html", "css", "js", "mjs", "json", "svg", "txt"]);
const forbidden = ["http://", "https://", "ws://", "wss://", "<base", "<iframe", "<object", "<embed", "eval(", "new function(", "import(", "file://"];
const root = resolve(process.argv[2] ?? "");
const shouldWrite = process.argv.includes("--write");

if (!process.argv[2]) throw new Error("usage: package.mjs <package-root> [--write]");

async function walk(directory, files = []) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const path = resolve(directory, entry.name);
    const stat = await lstat(path);
    if (stat.isSymbolicLink()) throw new Error(`symbolic link forbidden: ${entry.name}`);
    if (stat.isDirectory()) await walk(path, files);
    else if (stat.isFile()) files.push(path);
  }
  return files;
}

const files = (await walk(root)).sort((a, b) => {
  const left = relative(root, a).split(sep).join("/");
  const right = relative(root, b).split(sep).join("/");
  return left < right ? -1 : left > right ? 1 : 0;
});
if (files.length > 512) throw new Error("package has more than 512 files");
let total = 0;
const hash = createHash("sha256");

for (const file of files) {
  const path = relative(root, file).split(sep).join("/");
  if (!path || path.startsWith("/") || path.split("/").some((part) => !part || part === "." || part === "..")) {
    throw new Error(`invalid relative path: ${path}`);
  }
  const extension = path.includes(".") ? path.split(".").pop().toLowerCase() : "";
  if (!allowed.has(extension)) throw new Error(`unsupported file type: ${path}`);
  const bytes = await readFile(file);
  if (bytes.length > 16 * 1024 * 1024) throw new Error(`file exceeds 16 MiB: ${path}`);
  total += bytes.length;
  if (total > 64 * 1024 * 1024) throw new Error("package exceeds 64 MiB");
  if (textual.has(extension) && path !== manifestName) {
    const text = bytes.toString("utf8").toLowerCase();
    if (forbidden.some((needle) => text.includes(needle))) throw new Error(`forbidden offline content: ${path}`);
  }
  if (path !== manifestName) {
    hash.update(path);
    hash.update("\0");
    hash.update(bytes);
    hash.update("\0");
  }
}

const digest = hash.digest("hex");
const manifestPath = resolve(root, manifestName);
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
if (manifest.schema !== "hypha.room-template.v1" || manifest.sdk_version !== "1") {
  throw new Error("unsupported template schema or SDK");
}
manifest.integrity = { algorithm: "sha256", digest };
if (shouldWrite) await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
console.log(digest);
