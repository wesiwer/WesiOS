from pathlib import Path
import re

ROOT = Path('server/pb_hooks')
TARGETS = [
    'wesi_sync_context.pb.js',
    'wesi_sync_read.pb.js',
    'wesi_sync_write.pb.js',
    'wesi_sync_extra_runtime.js',
]
ACCESS = 'require(`${__hooks}/wesi_sync_data_access.js`)'

ASSIGN_FIRST_NULL = re.compile(
    r'try\s*\{\s*(\w+)\s*=\s*e\.app\.findFirstRecordByFilter\((.*?)\);\s*\}\s*catch\s*\([^)]*\)\s*\{\s*\1\s*=\s*null\s*;?\s*\}',
    re.S,
)
ASSIGN_ROWS_EMPTY = re.compile(
    r'try\s*\{\s*(\w+)\s*=\s*e\.app\.findRecordsByFilter\((.*?)\);\s*\}\s*catch\s*\([^)]*\)\s*\{\s*\1\s*=\s*\[\]\s*;?\s*\}',
    re.S,
)
ASSIGN_ROWS_RETHROW = re.compile(
    r'try\s*\{\s*(\w+)\s*=\s*e\.app\.findRecordsByFilter\((.*?)\);\s*\}\s*catch\s*\((\w+)\)\s*\{\s*throw\s+\3\s*;?\s*\}',
    re.S,
)

replacements = 0
changed = []
for name in TARGETS:
    path = ROOT / name
    text = path.read_text(encoding='utf-8')
    before = text

    text, n = ASSIGN_FIRST_NULL.subn(
        lambda m: f'{m.group(1)} = {ACCESS}.first(e.app, {m.group(2)});',
        text,
    )
    replacements += n
    text, n = ASSIGN_ROWS_EMPTY.subn(
        lambda m: f'{m.group(1)} = {ACCESS}.records(e.app, {m.group(2)});',
        text,
    )
    replacements += n
    text, n = ASSIGN_ROWS_RETHROW.subn(
        lambda m: f'{m.group(1)} = {ACCESS}.records(e.app, {m.group(2)});',
        text,
    )
    replacements += n

    if text != before:
        text = '\n'.join(line.rstrip() for line in text.splitlines()) + '\n'
        path.write_text(text, encoding='utf-8')
        changed.append(name)

if replacements < 15:
    raise SystemExit(f'expected at least 15 sync DB-read replacements, got {replacements}')

helper = ROOT / 'wesi_sync_data_access.js'
helper.write_text('''function boundedLimit(value) {\n  const parsed = Number(value);\n  if (!Number.isFinite(parsed) || parsed <= 0) return 10000;\n  return Math.min(10000, Math.max(1, Math.floor(parsed)));\n}\n\nmodule.exports = {\n  records: function(app, collection, filter, sort, maxRecords, offset, params) {\n    return app.findRecordsByFilter(\n      collection,\n      filter,\n      sort,\n      boundedLimit(maxRecords),\n      Number(offset || 0),\n      params || {},\n    );\n  },\n\n  first: function(app, collection, filter, params) {\n    const rows = module.exports.records(app, collection, filter, "id", 1, 0, params);\n    return rows.length ? rows[0] : null;\n  },\n};\n''', encoding='utf-8')

# The audited sync gateway must have one data-read contract. No route is allowed
# to reinterpret a storage error as an empty server or a missing record.
offenders = []
for name in TARGETS:
    text = (ROOT / name).read_text(encoding='utf-8')
    if 'e.app.findRecordsByFilter' in text:
        offenders.append(name + ': direct findRecordsByFilter remains')
    if 'e.app.findFirstRecordByFilter' in text:
        offenders.append(name + ': direct findFirstRecordByFilter remains')
if offenders:
    raise SystemExit('\n'.join(offenders))

contract = ROOT / 'wesi_sync_data_access_contract_test.mjs'
contract.write_text('''import assert from "node:assert/strict";\nimport fs from "node:fs";\nimport path from "node:path";\nimport {createRequire} from "node:module";\nimport {test} from "node:test";\n\nconst require = createRequire(import.meta.url);\nconst access = require(path.resolve("server/pb_hooks/wesi_sync_data_access.js"));\n\ntest("zero and invalid sync read limits are converted to a bounded positive read", () => {\n  const calls = [];\n  const app = {\n    findRecordsByFilter(...args) { calls.push(args); return []; },\n  };\n  access.records(app, "wesios_records", "owner='x'", "id", 0, 0, {});\n  access.records(app, "wesios_records", "owner='x'", "id", -5, 0, {});\n  assert.equal(calls[0][3], 10000);\n  assert.equal(calls[1][3], 10000);\n});\n\ntest("missing row and backend failure are different sync states", () => {\n  const empty = {findRecordsByFilter() { return []; }};\n  assert.equal(access.first(empty, "wesios_records", "rid='missing'", {}), null);\n\n  const broken = {findRecordsByFilter() { throw new Error("db unavailable"); }};\n  assert.throws(() => access.records(broken, "wesios_records", "id != ''", "id", 10, 0, {}), /db unavailable/);\n  assert.throws(() => access.first(broken, "wesios_records", "rid='x'", {}), /db unavailable/);\n});\n\ntest("all production sync gateway reads use the shared fail-closed contract", () => {\n  const files = [\n    "wesi_sync_context.pb.js",\n    "wesi_sync_read.pb.js",\n    "wesi_sync_write.pb.js",\n    "wesi_sync_extra_runtime.js",\n  ];\n  for (const name of files) {\n    const source = fs.readFileSync(path.resolve("server/pb_hooks", name), "utf8");\n    assert.equal(source.includes("e.app.findRecordsByFilter"), false, name);\n    assert.equal(source.includes("e.app.findFirstRecordByFilter"), false, name);\n    assert.equal(source.includes("wesi_sync_data_access.js"), true, name);\n  }\n});\n''', encoding='utf-8')

print('SYNC_DB_READ_REPLACEMENTS=', replacements)
print('CHANGED_SYNC_FILES=', ','.join(changed))
