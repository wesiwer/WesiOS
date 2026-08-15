from pathlib import Path

models = Path('lib/features/ai/runtime/wesi_resource_scheduler_models.dart')
text = models.read_text(encoding='utf-8')
old = "      (totalGpuVramMb == 0 || freeGpuVramMb <= totalGpuVramMb) &&\n"
new = "      freeGpuVramMb <= totalGpuVramMb &&\n"
if old not in text:
    raise SystemExit('GPU snapshot guard needle not found')
models.write_text(text.replace(old, new, 1), encoding='utf-8')

test_file = Path('test/wesi_resource_scheduler_test.dart')
test_text = test_file.read_text(encoding='utf-8')
needle = "    test('corrupt resource telemetry is rejected before routing', () {\n      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(\n        WesiLocalToolNames.pythonRun,\n      );\n      final result = scheduler.select(\n        job: requirements,\n        workers: <WesiWorkerResourceProfile>[\n          _worker(totalRamMb: 4096, availableRamMb: 8192),\n        ],\n      );\n      expect(result.ok, isFalse);\n      expect(result.blockerCode, WesiSchedulerBlockerCode.resourceSnapshot);\n    });\n\n"
addition = needle + "    test('GPU telemetry cannot report free VRAM when total VRAM is zero', () {\n      final requirements = WesiTrustedWorkloadRegistry.gpuMediaRequirements(\n        minFreeGpuVramMb: 1024,\n      );\n      final result = scheduler.select(\n        job: requirements,\n        workers: <WesiWorkerResourceProfile>[\n          _worker(totalGpuVramMb: 0, freeGpuVramMb: 4096),\n        ],\n      );\n      expect(result.ok, isFalse);\n      expect(result.blockerCode, WesiSchedulerBlockerCode.resourceSnapshot);\n    });\n\n"
if needle not in test_text:
    raise SystemExit('Scheduler regression insertion needle not found')
test_file.write_text(test_text.replace(needle, addition, 1), encoding='utf-8')

print('Stage 8 GPU snapshot fail-closed fix applied')
