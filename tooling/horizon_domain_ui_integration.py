from pathlib import Path


def patch(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        print('skip:', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('ok:', label)

# Audio Vault: expose contract memory in the actual lease UI and delete sidecar
# assumptions when the legal/business lease is removed.
service = 'lib/features/audio/services/audio_vault_service.dart'
screen = 'lib/features/audio/audio_vault_v2_screen.dart'
accounts = 'lib/features/treasury/widgets/accounts_bar.dart'

patch(
    service,
    """import '../../team/services/team_service.dart';
import '../models/audio_vault_models.dart';
""",
    """import '../../team/services/team_service.dart';
import '../../treasury/services/horizon_contract_memory.dart';
import '../models/audio_vault_models.dart';
""",
    'Audio Vault contract-memory import',
)
patch(
    service,
    """  static Future<BeatEntry> clearLease(BeatEntry beat) async {
    final taskId = beat.lease?.reminderTaskId;
""",
    """  static Future<BeatEntry> clearLease(BeatEntry beat) async {
    final leaseId = beat.lease?.id;
    if (leaseId != null && leaseId.isNotEmpty) {
      await HorizonContractMemoryService.removeLease(leaseId);
    }
    final taskId = beat.lease?.reminderTaskId;
""",
    'remove contract memory with closed lease',
)
patch(
    screen,
    """import 'widgets/audio_visualizer.dart';
import 'widgets/lease_countdown.dart';
""",
    """import 'widgets/audio_visualizer.dart';
import 'widgets/horizon_contract_dialog.dart';
import 'widgets/lease_countdown.dart';
""",
    'Audio Vault Horizon dialog import',
)
patch(
    screen,
    """              Row(children: [
                OutlinedButton.icon(
                    onPressed: () => _editLease(b),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Продлить / изменить')),
                const SizedBox(width: 8),
                TextButton.icon(
""",
    """              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () => _editLease(b),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Продлить / изменить')),
                OutlinedButton.icon(
                    onPressed: () => HorizonContractDialog.show(context, b),
                    icon: const Icon(Icons.query_stats),
                    label: const Text('Horizon: ожидания денег')),
                TextButton.icon(
""",
    'Audio Vault contract expectations button',
)

# Treasury accounts: per-location liquidity risk profile lives beside account
# settings and does not change the AccountModel Hive schema.
patch(
    accounts,
    """import '../services/account_service.dart';
""",
    """import '../services/account_service.dart';
import 'account_liquidity_dialog.dart';
""",
    'account liquidity dialog import',
)
patch(
    accounts,
    """      onTap: () => widget.onSelect(s.account.id),
      onEdit: () => _editAccount(s),
    );
""",
    """      onTap: () => widget.onSelect(s.account.id),
      onEdit: () => _editAccount(s),
      onRisk: () => AccountLiquidityDialog.show(context, s.account),
    );
""",
    'account liquidity action',
)
patch(
    accounts,
    """    VoidCallback? onEdit,
  }) {
""",
    """    VoidCallback? onEdit,
    VoidCallback? onRisk,
  }) {
""",
    'account card risk callback',
)
patch(
    accounts,
    """                  if (onEdit != null)
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.more_horiz,
                          size: 15, color: AppTheme.textMuted),
                    ),
""",
    """                  if (onRisk != null)
                    GestureDetector(
                      onTap: onRisk,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.shield_outlined,
                            size: 14, color: AppTheme.textMuted),
                      ),
                    ),
                  if (onEdit != null)
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.more_horiz,
                          size: 15, color: AppTheme.textMuted),
                    ),
""",
    'account card shield icon',
)

print('Audio Vault + account liquidity integration complete')
