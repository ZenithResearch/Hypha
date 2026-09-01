import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";

const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: true, strictRequired: false });

const outputValidate = ajv.compile(read("./out.schema.json"));
const outputFixtures = read("./out.schema.tests.json");
outputFixtures.valid.unshift({ label: "canonical v2 example", instance: read("./examples/out.v2.json") });
for (const fixture of outputFixtures.valid) {
  assert.equal(outputValidate(fixture.instance), true, fixture.label + " should be schema-valid: " + JSON.stringify(outputValidate.errors));
}
for (const fixture of outputFixtures.invalid) {
  assert.equal(outputValidate(fixture.instance), false, fixture.label + " should be schema-invalid");
}

const sdk = "../SDK/HyphaCanvasSDK";
const capability = read(`${sdk}/schemas/capability.schema.json`);
ajv.addSchema(capability);
const requestValidate = ajv.compile(read(`${sdk}/schemas/bridge-request.schema.json`));
const responseValidate = ajv.compile(read(`${sdk}/schemas/bridge-response.schema.json`));
const manifestValidate = ajv.compile(read(`${sdk}/schemas/template-manifest.schema.json`));
const referenceValidate = ajv.compile(read(`${sdk}/schemas/template-reference.schema.json`));

assert.equal(requestValidate(read(`${sdk}/fixtures/request-assets-list.json`)), true, JSON.stringify(requestValidate.errors));
assert.equal(responseValidate(read(`${sdk}/fixtures/response-assets-list.json`)), true, JSON.stringify(responseValidate.errors));
assert.equal(responseValidate(read(`${sdk}/fixtures/response-capability-denied.json`)), true, JSON.stringify(responseValidate.errors));
assert.equal(manifestValidate(read(`${sdk}/fixtures/template-manifest.json`)), true, JSON.stringify(manifestValidate.errors));
assert.equal(referenceValidate(read(`${sdk}/fixtures/template-reference.json`)), true, JSON.stringify(referenceValidate.errors));

const traversal = read(`${sdk}/fixtures/template-reference.json`);
traversal.source.path = "../escape.html";
assert.equal(referenceValidate(traversal), false, "Canvas references must reject path traversal");

console.log("out.json and Canvas contract fixtures passed");
