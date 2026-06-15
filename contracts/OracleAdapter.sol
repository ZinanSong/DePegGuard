// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OracleAdapter is Ownable {
    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    struct DepegState {
        uint256 breachStart;
        uint256 minPrice;
    }

    mapping(address => mapping(uint8 => DepegState)) public depegStates;
    mapping(address => Observation[12]) public observations;
    mapping(address => uint8) public obsIndex;
    mapping(address => uint256) public obsCount;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => address) public priceFeeds;

    address public nftContract;
    address public core;

    uint256[3] public thresholds = [
        970000000000000000,
        900000000000000000,
        800000000000000000
    ];

    uint256[3] public windows = [12 hours, 24 hours, 6 hours];

    uint256 public constant UPDATE_COOLDOWN = 30 minutes;
    uint256 public constant STALENESS_THRESHOLD = 2 hours;

    modifier onlyCoreOrNFT() {
        require(msg.sender == core || msg.sender == nftContract, "Not core/nft");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setNFTContract(address _nft) external onlyOwner {
        require(_nft != address(0), "NFT zero");
        nftContract = _nft;
    }

    function setCore(address _core) external onlyOwner {
        require(_core != address(0), "Core zero");
        core = _core;
    }

    function setPriceFeed(address stablecoin, address feed) external onlyOwner {
        require(stablecoin != address(0), "Stablecoin zero");
        require(feed != address(0), "Feed zero");
        priceFeeds[stablecoin] = feed;
    }

    function update(address stablecoin) external {
        require(
            block.timestamp >= lastUpdateTime[stablecoin] + UPDATE_COOLDOWN,
            "Too frequent"
        );
        _internalUpdate(stablecoin);
    }

    function forceUpdate(address stablecoin) external onlyCoreOrNFT {
        _internalUpdate(stablecoin);
    }

    function _internalUpdate(address stablecoin) internal {
        address feed = priceFeeds[stablecoin];
        require(feed != address(0), "Feed not set");

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(feed).latestRoundData();

        require(answer > 0, "Invalid price");
        require(updatedAt > 0, "Round incomplete");
        require(answeredInRound >= roundId, "Stale round");
        require(block.timestamp - updatedAt <= STALENESS_THRESHOLD, "Stale price");

        uint256 decimals = AggregatorV3Interface(feed).decimals();
        uint256 normalizedPrice = (uint256(answer) * 1e18) / (10 ** decimals);

        uint8 idx = obsIndex[stablecoin];
        observations[stablecoin][idx] = Observation({
            price: normalizedPrice,
            timestamp: block.timestamp
        });

        obsIndex[stablecoin] = (idx + 1) % 12;
        if (obsCount[stablecoin] < 12) obsCount[stablecoin]++;
        lastUpdateTime[stablecoin] = block.timestamp;

        uint256 twap = calculateTWAP(stablecoin);
        uint256 metric = (twap > 0) ? twap : normalizedPrice;

        _updateDepegState(stablecoin, 0, metric);
        _updateDepegState(stablecoin, 1, metric);
        _updateDepegState(stablecoin, 2, metric);
    }

    function calculateTWAP(address stablecoin) public view returns (uint256) {
        uint256 count = obsCount[stablecoin];
        if (count == 0) return 0;

        Observation[12] memory obs = observations[stablecoin];
        uint8 head = (count < 12) ? 0 : obsIndex[stablecoin];

        uint256 weightedSum = 0;
        uint256 totalTime = 0;

        for (uint256 i = 0; i + 1 < count; i++) {
            Observation memory a = obs[(head + i) % 12];
            Observation memory b = obs[(head + i + 1) % 12];
            if (a.timestamp == 0 || b.timestamp <= a.timestamp) continue;
            uint256 dt = b.timestamp - a.timestamp;
            weightedSum += a.price * dt;
            totalTime += dt;
        }

        Observation memory lastObs = obs[(head + count - 1) % 12];
        if (lastObs.timestamp > 0 && block.timestamp > lastObs.timestamp) {
            uint256 dtTail = block.timestamp - lastObs.timestamp;
            weightedSum += lastObs.price * dtTail;
            totalTime += dtTail;
        }

        if (totalTime == 0) return 0;
        return weightedSum / totalTime;
    }

    function _updateDepegState(address stablecoin, uint8 level, uint256 twap) internal {
        require(level < 3, "Invalid severity");
        DepegState storage state = depegStates[stablecoin][level];
        uint256 tau = thresholds[level];

        if (twap < tau) {
            if (state.breachStart == 0) {
                state.breachStart = block.timestamp;
                state.minPrice = twap;
            } else if (twap < state.minPrice) {
                state.minPrice = twap;
            }
        }
    }

    function getDepegStatus(address stablecoin, uint8 level) external view returns (bool, uint256) {
        require(level < 3, "Invalid severity");
        DepegState memory state = depegStates[stablecoin][level];
        if (state.breachStart == 0) return (false, 0);
        if (block.timestamp - state.breachStart >= windows[level]) {
            return (true, state.minPrice);
        }
        return (false, 0);
    }

    function getThreshold(uint8 level) external view returns (uint256) {
        require(level < 3, "Invalid severity");
        return thresholds[level];
    }
}
