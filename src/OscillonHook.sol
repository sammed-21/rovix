// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {
    SwapParams,
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/types/PoolOperation.sol";
// import {
//     OracleLibrary
// } from "v4-hooks-public/lib/briefcase/src/protocols/v3-periphery/libraries/OracleLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

interface IChainlinkOracle {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);
}

contract OscillonHook is BaseHook {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    /// @notice Chainlink USDC/USD oracle
    IChainlinkOracle public immutable USDC_ORACLE;

    /// @notice Peg threshold basis points (50 = 0.5%)
    uint256 public constant PEG_THRESHOLD_BPS = 50;

    /// @notice Max swap size during depeg (in token decimals)
    uint256 public constant MAX_DEPEG_SWAP = 10_000 * 1e18;

    event DepegDetected(uint256 depegBps, uint24 fee, uint256 swapSize);

    constructor(
        IPoolManager _poolManager,
        IChainlinkOracle _oracle
    ) BaseHook(_poolManager) {
        USDC_ORACLE = _oracle;
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
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
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

    /// @notice OscillonHook core: Dynamic fees on depeg
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        (
            uint256 twapDepegBps,
            uint24 fee,
            uint256 swapSize
        ) = _computeDepegAndFee(key, params);

        emit DepegDetected(twapDepegBps, fee, swapSize);

        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee
        );
    }

    function _computeDepegAndFee(
        PoolKey calldata key,
        SwapParams calldata params
    )
        internal
        view
        returns (uint256 twapDepegBps, uint24 fee, uint256 swapSize)
    {
        // 1. slot0
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());

        // 2. pool price
        uint256 poolPrice = (uint256(sqrtPriceX96) * sqrtPriceX96) >> 192;

        // 3. oracle price
        (, int256 oraclePrice, , uint256 updatedAt, ) = USDC_ORACLE
            .latestRoundData();
        require(block.timestamp <= updatedAt + 1 hours, "Stale oracle");

        uint256 pegPrice = uint256(oraclePrice);
        uint256 depegBps = poolPrice > pegPrice
            ? ((poolPrice - pegPrice) * 1e18) / pegPrice / 100
            : ((pegPrice - poolPrice) * 1e18) / pegPrice / 100;

        // 4. use current price as TWAP proxy
        twapDepegBps = depegBps;

        // 5. fee & limit
        fee = 300;
        if (twapDepegBps > PEG_THRESHOLD_BPS) {
            fee = 10_000;

            int256 amt = params.amountSpecified;
            if (amt < 0) {
                uint256 absAmount = uint256(-amt);
                require(absAmount <= MAX_DEPEG_SWAP, "Depeg swap limit");
            }
        } else if (twapDepegBps > 20) {
            fee = 5_000;
        }

        swapSize = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        return (twapDepegBps, fee, swapSize);
    }

    /// @notice Post-swap logging
    // function afterSwap(
    //     address,
    //     PoolKey calldata key,
    //     SwapParams calldata,
    //     BeforeSwapDelta,
    //     uint256
    // ) external override onlyPoolManager returns (bytes4) {
    //     return OscillonHook.afterSwap.selector;
    // }
}
