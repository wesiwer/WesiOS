from pathlib import Path

api = Path('lib/features/ai/connectors/wesi_connector_api.dart')
text = api.read_text(encoding='utf-8')
text = text.replace('intervalSeconds:interval.clamp(5,60)', 'intervalSeconds:interval.clamp(5,60).toInt()')
text = text.replace("retryAfterSeconds:((body['retryAfterSeconds'] as num?)?.toInt() ?? 5).clamp(1,60)", "retryAfterSeconds:((body['retryAfterSeconds'] as num?)?.toInt() ?? 5).clamp(1,60).toInt()")
api.write_text(text, encoding='utf-8')

sheet = Path('lib/features/ai/connectors/wesi_connector_manager_sheet.dart')
text = sheet.read_text(encoding='utf-8')
text = text.replace('Duration(seconds:seconds.clamp(5,60))', 'Duration(seconds:seconds.clamp(5,60).toInt())')
sheet.write_text(text, encoding='utf-8')
