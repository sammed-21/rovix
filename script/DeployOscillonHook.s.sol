// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-hooks-public/src/utils/HookMiner.sol";
import {OscillonHook, IChainlinkOracle} from "../src/OscillonHook.sol";

/// @notice Mines and deploys OscillonHook at a valid hook-flagged address.
/// @dev Required env vars:
/// - POOL_MANAGER
/// - ORACLE0
/// - STABLE0
/// - STABLE0_DECIMALS
/// - ORACLE1
/// - STABLE1
/// - STABLE1_DECIMALS
contract DeployOscillonHookScript is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address oracle0 = vm.envAddress("ORACLE0");
        address stable0 = vm.envAddress("STABLE0");
        uint8 stable0Decimals = uint8(vm.envUint("STABLE0_DECIMALS"));
        address oracle1 = vm.envAddress("ORACLE1");
        address stable1 = vm.envAddress("STABLE1");
        uint8 stable1Decimals = uint8(vm.envUint("STABLE1_DECIMALS"));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(manager, oracle0, stable0, stable0Decimals, oracle1, stable1, stable1Decimals);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(OscillonHook).creationCode, constructorArgs);

        vm.broadcast();
        OscillonHook deployed = new OscillonHook{salt: salt}(
            manager,
            IChainlinkOracle(oracle0),
            stable0,
            stable0Decimals,
            IChainlinkOracle(oracle1),
            stable1,
            stable1Decimals
        );
        require(address(deployed) == hookAddress, "hook address mismatch");
    }
}
