# OscillonHook

Inventory-risk protection hook for Uniswap v4 stable pools.

## Overview

`OscillonHook` is a `beforeSwap` hook that protects LPs during stablecoin depeg events.  
It monitors token-specific oracle prices, detects depeg severity, and applies directional controls:

- fee escalation under stress
- deep-depeg exact-in size caps
- severe-depeg circuit breaker (`PoolFrozen`)

This project is designed for stable/stable pools such as USDC/USDT or USDC/DAI.

## Problem

When one stablecoin depegs, traders can dump the weaker token into a pool and push inventory risk onto LPs.
Without dynamic controls, LPs absorb losses while arbitrage captures most upside.

OscillonHook adds policy logic to reduce that risk while keeping normal operation lightweight.

## How the Hook Works

Implementation: `src/OscillonHook.sol`

1. **Stable-only guard**
   - Pool tokens must match configured `STABLE0` and `STABLE1`.
   - Otherwise swap reverts with `UnsupportedStablePool()`.

2. **Token-specific oracle read**
   - Reads the oracle of the input stable token for the current swap direction.
   - Reverts on invalid/stale oracle data:
     - `Bad oracle`
     - `Stale oracle`

3. **Depeg detection**
   - Computes absolute deviation from $1 in basis points (`depegBps`).

4. **Policy**
   - Small depeg -> increased fee
   - Drain tier -> higher fee + exact-in cap
   - Severe depeg -> `PoolFrozen()` for dumping flow
   - Recovery window -> temporary restore fee after high-risk events

5. **Event**
   - Emits `DepegDetected(depegBps, fee, swapSize)` on each swap path.

## Current Policy Constants

- `SMALL_DEPEG_BPS = 7`
- `DRAIN_DEPEG_BPS = 20`
- `FREEZE_DEPEG_BPS = 60`
- `RESTORE_WINDOW = 1 hours`

Fee tiers (LP fee override pips):

- Base: `100` (~1 bps)
- Small depeg: `800` (~8 bps)
- Drain tier: `2800` (~28 bps)
- Restore tier: `30` (~0.3 bps)

## Security Notes

- Hook entrypoints are protected by `onlyPoolManager` through `BaseHook`.
- Non-pool-manager direct calls are expected to revert.
- Liquidity operations are not blocked by this hook policy:
  - `beforeAddLiquidity = false`
  - `beforeRemoveLiquidity = false`
  - `afterAddLiquidity = false`
  - `afterRemoveLiquidity = false`

## Tests

Test file: `test/OscillonHook.t.sol`

Covered scenarios:

- `test_scenarios_1_to_5_USDT_depeg_in_order()`
- `test_scenarios_1_to_5_USDC_depeg_in_order()`
- `test_beforeSwap_Reverts_WhenCalledByNonPoolManager()`

Run tests:

```bash
forge test -vvv
```

## Project Structure

- `src/OscillonHook.sol` - hook logic
- `test/OscillonHook.t.sol` - scenario and security tests
- `test/mock/MockV3Aggregator.sol` - oracle mock

## Build and Tooling

```bash
forge build
forge test
forge fmt
forge snapshot
```

## Limitations (MVP)

- Static thresholds and fee tiers (not governance-tunable yet)
- Single oracle feed per token (no fallback aggregation)
- Parameter calibration should be validated with deeper economic simulation
