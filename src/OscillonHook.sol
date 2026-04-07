// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

interface IChainlinkOracle {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);

    function decimals() external view returns (uint8);
}

contract OscillonHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    event DepegDetected(uint256 depegBps, uint24 fee, uint256 swapSize);

    error UnsupportedStablePool();
    error PoolFrozen();

    /// @notice Oracle and stable token configuration for stable token 0
    IChainlinkOracle public immutable ORACLE0;
    address public immutable STABLE0;
    uint8 public immutable ORACLE0_DECIMALS;
    uint256 public immutable MAX_DEPEG_SWAP0;

    /// @notice Oracle and stable token configuration for stable token 1
    IChainlinkOracle public immutable ORACLE1;
    address public immutable STABLE1;
    uint8 public immutable ORACLE1_DECIMALS;
    uint256 public immutable MAX_DEPEG_SWAP1;

    // Fee schedule (returned via lpFeeOverride) is in "hundredths of a bip"
    uint24 public constant BASE_FEE_PIPS = 100; // ~1 bps
    uint24 public constant SMALL_FEE_PIPS = 800; // ~8 bps
    uint24 public constant DRAIN_FEE_PIPS = 2800; // ~28 bps
    uint24 public constant RESTORE_FEE_PIPS = 30; // ~0.3 bps

    uint256 public constant SMALL_DEPEG_BPS = 7; // small depeg threshold
    uint256 public constant DRAIN_DEPEG_BPS = 20; // drain/deep depeg threshold
    uint256 public constant FREEZE_DEPEG_BPS = 60; // circuit breaker threshold
    uint256 public constant RESTORE_WINDOW = 1 hours;
j 
    uint256 public constant MAX_DEPEG_SWAP_FACTOR = 10_000; // exact-in cap factor

    mapping(PoolId => uint256) public lastHighDepegAt;

    constructor(
        IPoolManager _poolManager,
        IChainlinkOracle _oracle0,
        address _stable0,
        uint8 stableDecimals0,
        IChainlinkOracle _oracle1,
        address _stable1,
        uint8 stableDecimals1
    ) BaseHook(_poolManager) {
        ORACLE0 = _oracle0;
        STABLE0 = _stable0;
        ORACLE0_DECIMALS = _oracle0.decimals();
        MAX_DEPEG_SWAP0 =
            MAX_DEPEG_SWAP_FACTOR *
            (10 ** uint256(stableDecimals0));

        ORACLE1 = _oracle1;
        STABLE1 = _stable1;
        ORACLE1_DECIMALS = _oracle1.decimals();
        MAX_DEPEG_SWAP1 =
            MAX_DEPEG_SWAP_FACTOR *
            (10 ** uint256(stableDecimals1));

        require(_stable0 != _stable1, "STABLES_EQUAL");
    }

    /// @notice OscillonHook stablecoin permissions
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _readDepeg(
        IChainlinkOracle oracle,
        uint8 oracleDecimals
    ) internal view returns (uint256 depegBps, bool pegBelow) {
        (, int256 oraclePrice, , uint256 updatedAt, ) = oracle
            .latestRoundData();
        require(oraclePrice > 0, "Bad oracle");
        require(updatedAt <= block.timestamp, "Future oracle");
        require(block.timestamp - updatedAt <= 1 hours, "Stale oracle");

        // Normalize oracle price into 1e18 (peg is 1e18).
        uint256 pegPrice1e18 = (uint256(oraclePrice) * 1e18) /
            (10 ** uint256(oracleDecimals));
        pegBelow = pegPrice1e18 < 1e18;
    
        if (pegBelow) {
            depegBps = ((1e18 - pegPrice1e18) * 10_000) / 1e18;
        } else {
            depegBps = ((pegPrice1e18 - 1e18) * 10_000) / 1e18;
        }
    }

    function _selectFeeAndUpdate(
        PoolKey calldata key,
        uint256 depegBps,
        bool pegBelow,
        uint256 swapSize,
        bool tokenInIsStable0
    ) internal returns (uint24 fee) {
        PoolId poolId = key.toId();

        uint256 lastHigh = lastHighDepegAt[poolId];
        bool inRestoreWindow = lastHigh != 0 &&
            (block.timestamp - lastHigh) <= RESTORE_WINDOW;

        uint256 maxSwap = tokenInIsStable0 ? MAX_DEPEG_SWAP0 : MAX_DEPEG_SWAP1;

        fee = BASE_FEE_PIPS;

        // Circuit breaker: freeze when the input stable is severely off-peg in either direction.
        if (depegBps >= FREEZE_DEPEG_BPS) revert PoolFrozen();

        if (pegBelow) {
            // Update last depeg time when we're in the "drain" tier.
            if (depegBps >= DRAIN_DEPEG_BPS) {
                lastHighDepegAt[poolId] = block.timestamp;
                fee = DRAIN_FEE_PIPS;

                // Cap swap size for both exact-in and exact-out paths during deep depeg.
                require(swapSize <= maxSwap, "Depeg swap limit");
            } else if (depegBps >= SMALL_DEPEG_BPS) {
                fee = SMALL_FEE_PIPS;
            }
        }

        // Restore fee shortly after a high depeg ended.
        if (inRestoreWindow && depegBps <= SMALL_DEPEG_BPS) {
            fee = RESTORE_FEE_PIPS;
        }
    }

    /// @notice OscillonHook core: inventory-risk layer for a stable/stable pool.
    /// In severe depeg, swaps selling the depegged stable into the pool are frozen.
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Enforce "stable-only" pools by requiring both legs are configured stables.
        if (
            Currency.unwrap(key.currency0) != STABLE0 &&
            Currency.unwrap(key.currency0) != STABLE1
        ) {
            revert UnsupportedStablePool();
        }
        if (
            Currency.unwrap(key.currency1) != STABLE0 &&
            Currency.unwrap(key.currency1) != STABLE1
        ) {
            revert UnsupportedStablePool();
        }

        // Determine which stable is being sold into the pool.
        address tokenIn = params.zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);

        // Read depeg for the *input* stable only (directional asymmetry).
        uint256 depegBps;
        bool pegBelow;
        if (tokenIn == STABLE0) {
            (depegBps, pegBelow) = _readDepeg(ORACLE0, ORACLE0_DECIMALS);
        } else {
            (depegBps, pegBelow) = _readDepeg(ORACLE1, ORACLE1_DECIMALS);
        }

        // Calculate exact-in size magnitude (used for caps + event).
        uint256 swapSize = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        uint24 fee = _selectFeeAndUpdate(
            key,
            depegBps,
            pegBelow,
            swapSize,
            tokenIn == STABLE0
        );

        emit DepegDetected(depegBps, fee, swapSize);

        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }
}
