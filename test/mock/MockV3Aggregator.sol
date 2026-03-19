// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title MockV3Aggregator
/// @notice Mock Chainlink V3-style aggregator for tests. Compatible with IChainlinkOracle (latestRoundData).
contract MockV3Aggregator {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
        _updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /// @dev Returns (roundId, answer, startedAt, updatedAt, answeredInRound). updatedAt = block.timestamp so OscillonHook's staleness check passes.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _answer, _updatedAt, _updatedAt, 0);
    }

    /// @notice For tests that need to change oracle price (e.g. depeg scenarios)
    function updateAnswer(int256 answer_) external {
        _answer = answer_;
        _updatedAt = block.timestamp;
    }

    /// @notice For testing stale-oracle behavior.
    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }
}
