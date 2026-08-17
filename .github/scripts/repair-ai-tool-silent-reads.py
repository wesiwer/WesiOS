from pathlib import Path
import re

ROOT = Path('server/pb_hooks')
FILES = [
    'wesi_ai_audio_tools.js',
    'wesi_ai_crm_write_tools.js',
    'wesi_ai_finance_policy.js',
    'wesi_ai_finance_write_tools.js',
    'wesi_ai_knowledge_tools.js',
    'wesi_ai_roadmap_tools.js',
    'wesi_ai_task_tools.js',
    'wesi_ai_task_write_tools.js',
    'wesi_ai_team_tools.js',
    'wesi_ai_workspace_tools.js',
]
REQUIRE = 'const dataAccess = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_data_access.js");\n'

DIRECT_ROWS = re.compile(
    r'try\s*\{\s*return\s+e\.app\.findRecordsByFilter\((.*?)\);\s*\}\s*catch\s*\([^)]*\)\s*\{\s*return\s*\[\]\s*;?\s*\}',
    re.S,
)
DIRECT_FIRST = re.compile(
    r'try\s*\{\s*return\s+e\.app\.findFirstRecordByFilter\((.*?)\);\s*\}\s*catch\s*\([^)]*\)\s*\{\s*return\s+null\s*;?\s*\}',
    re.S,
)
ASSIGN_ROWS = re.compile(
    r'try\s*\{\s*(\w+)\s*=\s*e\.app\.findRecordsByFilter\((.*?)\);\s*\}\s*catch\s*\([^)]*\)\s*\{\s*(?:(?:\1\s*=\s*\[\]\s*;?)|(?:return\s*\[\]\s*;?))?\s*\}',
    re.S,
)
ASSIGN_FIRST = re.compile(
    r'try\s*\{\s*(\w+)\s*=\s*e\.app\.findFirstRecordByFilter\((.*?)\);\s*\}\s*catch\s*\([^)]*\)\s*\{\s*(?:(?:\1\s*=\s*null\s*;?)|(?:return\s+null\s*;?))?\s*\}',
    re.S,
)

changed = []
replacements = 0
for name in FILES:
    path = ROOT / name
    text = path.read_text(encoding='utf-8')
    before = text

    text, n = DIRECT_ROWS.subn(lambda m: f'return dataAccess.records(e.app, {m.group(1)});', text)
    replacements += n
    text, n = DIRECT_FIRST.subn(lambda m: f'return dataAccess.first(e.app, {m.group(1)});', text)
    replacements += n
    text, n = ASSIGN_ROWS.subn(lambda m: f'{m.group(1)} = dataAccess.records(e.app, {m.group(2)});', text)
    replacements += n
    text, n = ASSIGN_FIRST.subn(lambda m: f'{m.group(1)} = dataAccess.first(e.app, {m.group(2)});', text)
    replacements += n

    if text != before:
        if 'wesi_ai_data_access.js' not in text:
            text = REQUIRE + text
        path.write_text(text, encoding='utf-8')
        changed.append(name)

if replacements < 14:
    raise SystemExit(f'expected at least 14 silent data-read replacements, got {replacements}')

# Every DB read in these internal adapters must now go through the shared helper.
# This makes an unavailable backend distinguishable from a legitimate empty set.
offenders = []
for name in FILES:
    text = (ROOT / name).read_text(encoding='utf-8')
    if 'e.app.findRecordsByFilter' in text or 'e.app.findFirstRecordByFilter' in text:
        offenders.append(name)
if offenders:
    raise SystemExit('direct internal tool DB reads remain:\n' + '\n'.join(offenders))

broker = ROOT / 'wesi_ai_action_broker.js'
text = broker.read_text(encoding='utf-8')
old = '''  } catch (_) {\n    result = {ok: false, code: "WAI_TOOL_EXECUTION_FAILED", message: "Не удалось выполнить действие WesiOS"};\n  }'''
new = '''  } catch (error) {\n    const taggedCode = error && error.wesiCode ? String(error.wesiCode) : "";\n    const taggedMessage = error && error.wesiMessage ? String(error.wesiMessage) : "";\n    result = {\n      ok: false,\n      code: taggedCode || "WAI_TOOL_EXECUTION_FAILED",\n      message: taggedMessage || "Не удалось выполнить действие WesiOS",\n    };\n  }'''
if old not in text:
    raise SystemExit('action broker catch anchor not found')
text = text.replace(old, new, 1)
broker.write_text(text, encoding='utf-8')

helper = ROOT / 'wesi_ai_data_access.js'
helper.write_text('''function unavailable(error) {\n  const wrapped = new Error("WesiOS tool data read failed");\n  wrapped.wesiCode = "WAI_TOOL_DATA_UNAVAILABLE";\n  wrapped.wesiMessage = "Не удалось прочитать данные WesiOS";\n  if (error) wrapped.cause = error;\n  return wrapped;\n}\n\nmodule.exports = {\n  records: function(app, collection, filter, sort, maxRecords, offset, params) {\n    try {\n      return app.findRecordsByFilter(collection, filter, sort, maxRecords, offset, params);\n    } catch (error) {\n      throw unavailable(error);\n    }\n  },\n\n  first: function(app, collection, filter, params) {\n    const rows = module.exports.records(app, collection, filter, "id", 1, 0, params);\n    return rows.length ? rows[0] : null;\n  },\n};\n''', encoding='utf-8')

contract = ROOT / 'wesi_ai_tool_data_access_contract_test.mjs'
contract.write_text('''import assert from "node:assert/strict";\nimport fs from "node:fs";\nimport path from "node:path";\nimport {createRequire} from "node:module";\nimport {test} from "node:test";\n\nconst require = createRequire(import.meta.url);\nglobalThis.__hooks = path.resolve("server/pb_hooks");\nconst dataAccess = require(path.resolve("server/pb_hooks/wesi_ai_data_access.js"));\nconst broker = require(path.resolve("server/pb_hooks/wesi_ai_action_broker.js"));\n\nconst internalAdapters = [\n  "wesi_ai_audio_tools.js",\n  "wesi_ai_crm_write_tools.js",\n  "wesi_ai_finance_policy.js",\n  "wesi_ai_finance_write_tools.js",\n  "wesi_ai_knowledge_tools.js",\n  "wesi_ai_roadmap_tools.js",\n  "wesi_ai_task_tools.js",\n  "wesi_ai_task_write_tools.js",\n  "wesi_ai_team_tools.js",\n  "wesi_ai_workspace_tools.js",\n];\n\ntest("shared data helper distinguishes empty rows from backend failure", () => {\n  const empty = {findRecordsByFilter() { return []; }};\n  assert.deepEqual(dataAccess.records(empty, "wesios_records", "id != ''", "id", 10, 0, {}), []);\n  assert.equal(dataAccess.first(empty, "wesios_records", "id='missing'", {}), null);\n\n  const broken = {findRecordsByFilter() { throw new Error("db down"); }};\n  assert.throws(\n    () => dataAccess.records(broken, "wesios_records", "id != ''", "id", 10, 0, {}),\n    (error) => error && error.wesiCode === "WAI_TOOL_DATA_UNAVAILABLE",\n  );\n});\n\ntest("action broker preserves safe tagged tool failures", () => {\n  const adapter = {\n    execute() {\n      const error = new Error("private db error");\n      error.wesiCode = "WAI_TOOL_DATA_UNAVAILABLE";\n      error.wesiMessage = "Не удалось прочитать данные WesiOS";\n      throw error;\n    },\n  };\n  const result = broker.execute(\n    {app: {}},\n    {ownerId: "owner", employeeId: "owner", isOwner: true},\n    adapter,\n    "tasks_list",\n    {},\n    "org_wesi_inc",\n    {persona: "zane", conversationId: "c", requestId: "r"},\n  );\n  assert.equal(result.ok, false);\n  assert.equal(result.code, "WAI_TOOL_DATA_UNAVAILABLE");\n  assert.equal(result.message, "Не удалось прочитать данные WesiOS");\n});\n\ntest("internal tool adapters cannot silently convert DB failures to empty state", () => {\n  for (const name of internalAdapters) {\n    const source = fs.readFileSync(path.resolve("server/pb_hooks", name), "utf8");\n    assert.equal(source.includes("e.app.findRecordsByFilter"), false, name + " has a direct records read");\n    assert.equal(source.includes("e.app.findFirstRecordByFilter"), false, name + " has a direct first-record read");\n    assert.equal(source.includes("wesi_ai_data_access.js"), true, name + " does not use shared data access");\n  }\n});\n''', encoding='utf-8')

print('SILENT_READ_REPLACEMENTS=', replacements)
print('CHANGED_INTERNAL_ADAPTERS=', ','.join(changed))
