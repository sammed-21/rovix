// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Use these (matching BaseHook / @uniswap/v4-core):
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    SwapParams,
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

contract PointsHook is BaseHook, ERC1155 {
    constructor(IPoolManager _manager) BaseHook(_manager) {}

    // Set up hook permissions to return `true`
    // for the two hook functions we are using
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
                afterAddLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // Implement the ERC1155 `uri` function
    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    // Stub implementation of `afte rSwap`
    // 1. Make sure this is a ETH - TOken POol
    // 2. Make sure this swap is to buy Token in exchange for ETH
    // 3. Mint points equal to 20% of the amount of ETH being swapped in

    // this will help when you want to that stable coin should the one to swap in
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        //validate that this is an ETH/ TOken pool
        // We'll add more code here shortly

        if (!key.currency0.isAddressZero()) {
            return (this.afterSwap.selector, 0);
        }

        // validate that the currency1 is TOken
        // TODO: Currently don't have the token address

        // we only mint if the user swap buy token with eth

        if (!swapParams.zeroForOne) {
            return (this.afterSwap.selector, 0);
        }

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointForSwap = ethSpendAmount / 5;
        _assignPoints((key.toId()), hookData, pointForSwap);

        return (this.afterSwap.selector, 0);
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (!key.currency0.isAddressZero()) {
            return (BaseHook.afterAddLiquidity.selector, delta);
        }

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointForSwap = ethSpendAmount / 5;
        _assignPoints((key.toId()), hookData, pointForSwap);

        return (BaseHook.afterAddLiquidity.selector, delta);
    }

    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        if (hookData.length == 0) return;

        address user = abi.decode(hookData, (address));

        if (user == address(0)) return;

        uint poolIdUint = uint256(PoolId.unwrap(poolId));

        _mint(user, poolIdUint, points, "");
    }
}
