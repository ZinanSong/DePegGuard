// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal Chainlink-style Aggregator mock for tests.
contract MockV3Aggregator {
    uint8 public immutable decimals;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        _roundId = 1;
        _answer = _initialAnswer;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
    }

    /// @dev Testing-only price update function.
    function setAnswer(int256 newAnswer) external {
        require(newAnswer > 0, "answer<=0");
        _roundId += 1;
        _answer = newAnswer;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }
}
