// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";
import {MockV3Aggregator} from "./mock/MockV3Aggregator.sol";

import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";

import {OscillonHook} from "../src/OscillonHook.sol";
contract TestOscillonHook is Test, Deployers {
    MockERC20 token; // our token to use in the ETH-TOKEN pool

    // Native tokens are represented by address(0)
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    OscillonHook hook;

    function setUp() public {
        // step 1 +2
        //deploy poolmanager and router contracts
        deployFreshManagerAndRouters();
        MockV3Aggregator oracle = new MockV3Aggregator(18, int256(1e18));

        // Deploy TOKENS contract
        token = new MockERC20("USD Coin", "USDC", 18);
        tokenCurrency = Currency.wrap(address(token));

        //mint a tokens to overselve and address(1)
        token.mint(address(this), type(uint128).max);
        token.mint(address(1), type(uint128).max);

        // Deploy hook to a address that has proper flags set
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(manager, address(oracle));
        deployCodeTo("OscillonHook", constructorArgs, address(flags));

        hook = OscillonHook(payable(address(flags)));

        //appove our token for spending on the swap router and modify liquidity router
        //this varables are coming from the depltoers contract

        token.approve(address(swapRouter), type(uint128).max);
        token.approve(address(modifyLiquidityRouter), type(uint128).max);

        (key, ) = initPool(
            ethCurrency,
            tokenCurrency,
            IHooks(address(hook)),
            3000,
            SQRT_PRICE_1_1
        );

        //add some liqudiity to the pool
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.003 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickUpper,
            ethToAdd
        );

        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            liquidityDelta
        );
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    // function test_swap() public {
    //     uint256 poolIdUnit = uint256(PoolId.unwrap(key.toId()));
    //     uint256 pointsBalanceOriginal = hook.balanceOf(
    //         address(this),
    //         poolIdUnit
    //     );

    //     //set user address in hook data
    //     bytes memory hookData = abi.encode(address(this));

    //     //Now we swap
    //     // we will swap 0.001 ether for tokens
    //     // we should get 20% of 0.001 * 10**18 points
    //     // = 2 * 10**14

    //     swapRouter.swap{value: 0.001 ether}(
    //         key,
    //         IPoolManager.SwapParams({
    //             zeroForOne: true,
    //             amountSpecified: -int256(0.001 ether),
    //             sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //         }),
    //         PoolSwapTest.TestSettings({
    //             takeClaims: false,
    //             settleUsingBurn: false
    //         }),
    //         hookData
    //     );
    //     uint256 pointsBalanceAfterSwap = hook.balanceOf(
    //         address(this),
    //         poolIdUnit
    //     );
    //     assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
    // }
}
