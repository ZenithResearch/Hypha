import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import Ajv2020 from "ajv/dist/2020.js";

const schemaURL = new URL("./out.schema.json", import.meta.url);
const exampleURL = new URL("./examples/out.v2.json", import.meta.url);
const schema = JSON.parse(await readFile(schemaURL, "utf8"));
const canonicalExample = JSON.parse(await readFile(exampleURL, "utf8"));
const validate = new Ajv2020({
  allErrors: true,
  strict: true,
  // JSON Schema permits `required` in a subschema while `properties` lives in its parent.
  strictRequired: false,
}).compile(schema);

function assertSchemaValid(instance, label) {
  const valid = validate(instance);
  assert.equal(
    valid,
    true,
    `${label} should be schema-valid:\n${JSON.stringify(validate.errors, null, 2)}`,
  );
}

function assertSchemaInvalid(instance, label) {
  const valid = validate(instance);
  assert.equal(valid, false, `${label} should be schema-invalid`);
}

assertSchemaValid(canonicalExample, "canonical v2 example");
assertSchemaValid(
  { viewer: "quickLook", path: "deck.pptx", format: "pptx" },
  "unversioned v1",
);
assertSchemaValid(
  { version: 1, viewer: "quickLook", path: "deck.pptx", format: "pptx" },
  "explicit v1",
);
assertSchemaValid(
  {
    version: 2,
    primary: "site",
    path: "site/index.html",
    artifacts: [{ id: "site", path: "site/index.html", bundle_root: "site" }],
  },
  "HTML bundle inferred from path",
);
assertSchemaValid(
  {
    version: 2,
    primary: "site",
    path: "site/.assets/index.html",
    artifacts: [
      { id: "site", path: "site/.assets/index.html", bundle_root: "site/.assets" },
    ],
  },
  "hidden path component",
);
assertSchemaValid(
  {
    version: 2,
    primary: "site",
    path: "site/index.HTML",
    artifacts: [
      { id: "site", path: "site/index.HTML", format: "HTML", bundle_root: "site" },
    ],
  },
  "case-insensitive declared HTML format",
);
assertSchemaValid(
  {
    version: 2,
    primary: "brief",
    path: "brief.pdf",
    viewer: "quickLook",
    artifacts: [{ id: "brief", path: "brief.pdf", viewer: "pdf" }],
  },
  "PDF artifact and old-client mirror",
);
assertSchemaValid(
  {
    version: 2,
    primary: "notes",
    path: "notes.md",
    viewer: "text",
    artifacts: [{ id: "notes", path: "notes.md", viewer: "markdown" }],
  },
  "Markdown artifact and old-client mirror",
);

assertSchemaInvalid(
  { viewer: "slideshow", path: "deck.pptx", format: "pptx" },
  "slideshow in v1",
);
for (const viewer of ["slideshow", "pdf", "markdown"]) {
  assertSchemaInvalid(
    {
      version: 2,
      primary: "deck",
      path: "deck.pptx",
      viewer,
      artifacts: [{ id: "deck", path: "deck.pptx", viewer: "slideshow" }],
    },
    `artifact-only top-level viewer ${viewer}`,
  );
}
for (const path of [
  ".",
  "./artifact.txt",
  "artifact/.",
  " artifact.txt",
  "artifact.txt ",
  "artifact//file.txt",
  "artifact/../file.txt",
  "C:/artifact.txt",
  "artifact\\file.txt",
  "artifact\u007ffile.txt",
]) {
  assertSchemaInvalid(
    {
      version: 2,
      primary: "artifact",
      path,
      artifacts: [{ id: "artifact", path }],
    },
    `strict path ${JSON.stringify(path)}`,
  );
}
assertSchemaInvalid(
  {
    version: 2,
    primary: "site",
    path: "site/index.txt",
    artifacts: [{ id: "site", path: "site/index.txt", bundle_root: "site" }],
  },
  "bundle root without an HTML effective format",
);
assertSchemaInvalid(
  {
    version: 2,
    primary: "site",
    path: "site/index.html",
    artifacts: [
      { id: "site", path: "site/index.html", format: "pdf", bundle_root: "site" },
    ],
  },
  "bundle root with a non-HTML declared format",
);
assertSchemaInvalid(
  {
    version: 2,
    primary: "site",
    path: "site/index.html",
    artifacts: [
      { id: "site", path: "site/index.html", viewer: "text", bundle_root: "site" },
    ],
  },
  "bundle root with a non-web declared viewer",
);

console.log("out.schema.json: all conformance fixtures passed");
