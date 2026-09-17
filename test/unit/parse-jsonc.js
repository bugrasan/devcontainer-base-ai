#!/usr/bin/env node
// Parse a JSONC file (comments, trailing commas) with the same parser VS Code
// uses and print it as strict JSON, so the rest of the tests can use jq.
// Exits non-zero, with the offending offset, on a syntax error.
//
// Usage: node parse-jsonc.js <file>
process.env.NODE_PATH = require('child_process').execSync('npm root -g').toString().trim();
require('module')._initPaths();

const { parse, printParseErrorCode } = require('jsonc-parser');
const fs = require('fs');

const file = process.argv[2];
if (!file) {
    console.error('usage: parse-jsonc.js <file>');
    process.exit(2);
}

const errors = [];
const result = parse(fs.readFileSync(file, 'utf8'), errors, {
    allowTrailingComma: true,
    disallowComments: false,
});

if (errors.length > 0) {
    for (const e of errors) {
        console.error(`${file}: ${printParseErrorCode(e.error)} at offset ${e.offset}`);
    }
    process.exit(1);
}
process.stdout.write(JSON.stringify(result, null, 2));
