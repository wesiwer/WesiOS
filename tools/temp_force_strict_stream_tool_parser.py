from pathlib import Path

p = Path('server/wesi-ai-stream/gateway.mjs')
s = p.read_text(encoding='utf-8')
old = """    const name = String(tool.name || '').trim();\n    const hasArguments = Object.prototype.hasOwnProperty.call(tool, 'arguments');\n    if (hasArguments && (!tool.arguments || typeof tool.arguments !== 'object' || Array.isArray(tool.arguments))) {\n      return null;\n    }\n    const args = hasArguments ? tool.arguments : {};\n    return name ? {name, arguments: args} : null;\n"""
new = """    const name = String(tool.name || '').trim();\n    const hasArguments = Object.prototype.hasOwnProperty.call(tool, 'arguments');\n    // Explicit model-provided arguments must be a plain object. Never coerce\n    // malformed strings/arrays/null into {}, because that turns an invalid\n    // reserved tool envelope into a different valid call.\n    const malformedArguments = hasArguments && (\n      !tool.arguments || typeof tool.arguments !== 'object' || Array.isArray(tool.arguments)\n    );\n    if (malformedArguments) return null;\n    const args = hasArguments ? tool.arguments : {};\n    return name ? {name, arguments: args} : null;\n"""
if old not in s:
    raise SystemExit('strict parser anchor missing')
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('strict stream tool parser touched explicitly')
