import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { HyphaCanvasClient, viewerURL } from "./src/index.js";

const execFileAsync = promisify(execFile);
const sdkRoot = dirname(fileURLToPath(import.meta.url));

const requiredText = new Map(await Promise.all([
  "schemas/bridge-response.schema.json",
  "schemas/capability.schema.json",
  "schemas/template-manifest.schema.json",
  "schemas/template-reference.schema.json",
  "fixtures/response-assets-list.json",
  "fixtures/response-capability-denied.json"
].map(async (name) => [name, await readFile(join(sdkRoot, name), "utf8")])));

function requireText(relativePath) {
  return requiredText.get(relativePath);
}


test("emits the canonical version-one request", async () => {
  let envelope;
  const bridge = { postMessage(value) { envelope = value; } };
  const client = new HyphaCanvasClient(bridge);
  const operation = client.assets("deck", "slides/");
  assert.equal(envelope.v, 1);
  assert.equal(envelope.method, "assets.list");
  assert.deepEqual(envelope.params, { repository_id: "deck", prefix: "slides/" });
  globalThis.__hyphaBridgeReceive({ v: 1, id: envelope.id, ok: true, result: [] });
  assert.deepEqual(await operation, []);
});

test("viewer links use the trusted navigation route", () => {
  assert.equal(viewerURL("deck:slides/one.pptx"), "hypha-viewer://open/?asset_id=deck%3Aslides%2Fone.pptx");
});


test("schemas, fixtures, and Rust use the same bridge vocabulary", async () => {
  const requestSchema = JSON.parse(await readFile(join(sdkRoot, "schemas/bridge-request.schema.json"), "utf8"));
  const methods = requestSchema.properties.method.enum;
  const rust = await readFile(join(sdkRoot, "rust/src/lib.rs"), "utf8");
  for (const method of methods) assert.match(rust, new RegExp(`"${method.replace(".", "\\.")}"`));

  const request = JSON.parse(await readFile(join(sdkRoot, "fixtures/request-assets-list.json"), "utf8"));
  assert.ok(methods.includes(request.method));
  for (const name of [
    "schemas/bridge-response.schema.json",
    "schemas/capability.schema.json",
    "schemas/template-manifest.schema.json",
    "schemas/template-reference.schema.json",
    "fixtures/response-assets-list.json",
    "fixtures/response-capability-denied.json"
  ]) {
    assert.doesNotThrow(() => JSON.parse(requireText(name)));
  }
});

test("package validator writes a deterministic digest and rejects remote content", async () => {
  const root = await mkdtemp(join(tmpdir(), "hypha-canvas-sdk-"));
  try {
    await writeFile(join(root, "index.html"), "<!doctype html><title>Room</title>\n");
    await writeFile(join(root, "hypha-room-template.json"), JSON.stringify({
      schema: "hypha.room-template.v1",
      entry: "index.html",
      sdk_version: "1",
      capabilities: [],
      integrity: { algorithm: "sha256", digest: "0".repeat(64) }
    }));
    const script = join(sdkRoot, "scripts/package.mjs");
    const first = (await execFileAsync(process.execPath, [script, root, "--write"])).stdout.trim();
    const second = (await execFileAsync(process.execPath, [script, root])).stdout.trim();
    assert.match(first, /^[a-f0-9]{64}$/);
    assert.equal(second, first);
    const manifest = JSON.parse(await readFile(join(root, "hypha-room-template.json"), "utf8"));
    assert.equal(manifest.integrity.digest, first);

    await writeFile(join(root, "index.html"), "<script src=\"https://example.invalid/x.js\"></script>");
    await assert.rejects(execFileAsync(process.execPath, [script, root]));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
