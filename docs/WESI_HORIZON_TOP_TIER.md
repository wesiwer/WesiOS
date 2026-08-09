# Wesi Horizon — top-tier implementation contract

This document is the engineering contract for the A→G upgrade approved on 2026-08-09. It intentionally treats calibration and honesty as prerequisites for sophistication.

## Non-negotiable invariants

- 2–4 week accuracy is optimized before long-range cosmetics.
- 3–12 month forecasts mean-revert and become less certain; no permanent extrapolation of a good month.
- Recurring/committed cash is never blended into generic random noise.
- P10/P50/P90 and gap probabilities are calibrated against realized history.
- A dumb Combined forecast may never replace a better single engine.
- Sparse history must say “low confidence / insufficient evidence”, never fake a narrow interval.
- UI seed may be stable; evaluation uses multiple seeds.
- Every material forecast kink must have an explanation source.
- Decision outputs (runway, reserve, free buffer, risk thresholds, prompts) are first-class results.

## Delivery order

### Sprint A — honesty foundation (1–6)
- [x] mean reversion to long-run baseline
- [x] decay of recent pace and explicit drift cap
- [x] horizon-decaying weekly seasonality
- [x] uncertainty widening with horizon without inflating distant P50
- [x] paired 3–7 day block bootstrap
- [x] horizon-specific behavior and honest low-data confidence
- [x] lucky/shock episodes cannot masquerade as permanent recent baseline

### Sprint B — calibration (7–11)
- [x] coverage-driven interval scaling model
- [x] empirical gap-risk probability calibration bins
- [x] median bias correction
- [x] rolling 14/30/90/180 day backtests
- [x] multi-seed evaluation while UI keeps deterministic seed

### Sprint C — cash structure (12–16)
- [x] committed vs uncertain event primitives in Horizon core
- [x] recurring reliability weighting from realized evidence
- [x] separate income and expense shock pools
- [x] frequency × non-zero amount modeling
- [x] category/stream-first modeling before aggregation
- [x] company data sources wired into the primitives

### Sprint D — regimes and stress (17–20)
- [x] stable/growth/downturn regime detector
- [x] explicit Markov transitions so regimes are not permanent
- [x] default stress library: income −30%/60d, incoming delay 30d, large expense, main-source loss
- [x] Base / Conservative / Aggressive / Stress package in orchestration and decision UI

### Sprint E — decision layer (21–25)
- [x] runway and 10% / 25% gap-risk thresholds
- [x] reserve from simulated maximum drawdown
- [x] safety buffer = cash − stochastic reserve − near-term committed outflows, with no double counting
- [x] action prompts and behavioral warnings
- [x] What-If reports direct risk/runway delta, not only a new line
- [x] Forecast and Sandbox expose the decision panel before the chart

### Sprint F — learning and engine competition (26–29)
- [x] monthly persisted bounded learning loop
- [x] champion selection by backtest, not visual preference
- [x] quantile-loss metric and quantile calibration
- [x] separate champions by horizon
- [x] Combined uses the backtest winner and explicitly rejects equal averaging when it loses

### Sprint G — company cash control (30–35)
- [x] Treasury + Tasks + recurring + obligations business-context aggregator
- [x] Tasks can carry committed or probabilistic cash impact without a Hive schema migration
- [x] Audio Vault contract/renewal/royalty memory with conservative defaults
- [x] transaction-rhythm, recurring-miss and concentration early warnings
- [x] account-level liquidity/netting risk with local minimum, currency and FX haircut
- [x] per-day explanation primitives for material curve breaks
- [x] truth-first confidence state and explicit known/unknown cash share

## Product wiring

- `TreasuryService.generateForecast` is the company-level orchestration point. It combines native Treasury history, learned calibration, CRM probabilistic pipeline, task cash commitments, Audio Vault expectations and account liquidity snapshots.
- `ForecastEngine` remains pure/deterministic given inputs, seed and `asOf`; persistence and cross-module reads stay outside the math core.
- `TaskCashImpact` is encoded in existing task tags and therefore does not change the Task Hive schema.
- `HorizonContractMemoryService` and `AccountLiquidityService` use sidecar storage so legal/account records are not mutated by forecast assumptions.
- Sandbox uses the same Horizon math and risk/scenario package but intentionally does not import real CRM/Tasks/Vault/account context.
- Prophet/SARIMAX remain optional external engines; their absence is fail-soft. Wesi Horizon remains always available.

## Validation gates

The branch is not considered merge-ready until all of these are green on the final clean head:

1. `flutter analyze --no-fatal-infos`.
2. Entire `flutter test` suite.
3. `test/horizon_top_tier_test.dart` plus legacy `test/treasury_engines_test.dart` preserve both new and old mathematical invariants.
4. `test/horizon_product_integration_test.dart` verifies Tasks/Vault/accounts/Decision UI wiring and finite stress semantics.
5. Repository build verification workflows stay green.

The focused mathematical gate has already passed **33/33** tests after the final anti-millionaire fixes. A full clean CI is still the final authority before merge.

## Release state

This work is intentionally isolated in draft PR #66 / branch `agent/horizon-top-tier`. It has **not** been merged to `main` and **has not** been released to production. Production release remains out of scope until the owner explicitly requests it.