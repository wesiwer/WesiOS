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
- [x] uncertainty widening with horizon
- [x] paired 3–7 day block bootstrap
- [x] horizon-specific behavior and honest low-data confidence

### Sprint B — calibration (7–11)
- [x] coverage-driven interval scaling model
- [x] empirical gap-risk probability calibration bins
- [x] median bias correction
- [x] rolling 14/30/90/180 day backtests
- [x] multi-seed evaluation while UI keeps deterministic seed

### Sprint C — cash structure (12–16)
- [x] committed vs uncertain event primitives in Horizon core
- [x] recurring reliability weighting in core
- [x] separate income and expense shock pools
- [x] frequency × non-zero amount modeling
- [x] category/stream-first modeling before aggregation
- [ ] wire company data sources into the primitives

### Sprint D — regimes and stress (17–20)
- [x] stable/growth/downturn regime detector
- [x] explicit Markov transitions so regimes are not permanent
- [ ] default stress library
- [ ] Base / Conservative / Aggressive / Stress package in orchestration/UI

### Sprint E — decision layer (21–25)
- [x] runway and 10% / 25% gap-risk thresholds in core
- [x] reserve from simulated maximum drawdown
- [x] safety buffer = cash − reserve − near-term commitments
- [x] action-prompt primitives and behavioral warnings
- [ ] wire What-If to direct risk/runway delta and surface it in UI

### Sprint F — learning and engine competition (26–29)
- [ ] monthly persisted learning loop
- [ ] champion selection by backtest, not visual preference
- [x] quantile-loss metric and quantile calibration primitives
- [ ] separate champions by horizon and non-dumb Combined

### Sprint G — company cash control (30–35)
- [ ] Treasury + Tasks + recurring + obligations business-context aggregator
- [ ] Audio Vault contract/renewal/royalty memory
- [x] transaction-rhythm early warnings in Horizon core
- [x] account-level liquidity/netting risk primitives
- [x] per-day explanation primitives
- [x] truth-first confidence state

The unchecked items are implementation work still required in this branch before merge. Production release is explicitly out of scope until the owner separately requests it.
