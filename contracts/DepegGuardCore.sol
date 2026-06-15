// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./InsurancePool.sol";
import "./CoverNFT.sol";
import "./OracleAdapter.sol";

contract DepegGuardCore {
    struct DepegEvent {
        address stablecoin;
        uint8 severity;
        uint256 tau;
        uint256 minPrice;
        uint256 timestamp;
        bool settled;
    }

    address public owner;
    uint256 public nextEventId;
    mapping(uint256 => DepegEvent) public events;
    mapping(address => mapping(uint8 => uint256)) public activeEventPlusOne;

    CoverNFT public nft;
    InsurancePool public pool;
    OracleAdapter public oracle;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _nft, address _pool, address _oracle) {
        require(_nft != address(0) && _pool != address(0) && _oracle != address(0), "Zero addr");
        owner = msg.sender;
        nft = CoverNFT(_nft);
        pool = InsurancePool(_pool);
        oracle = OracleAdapter(_oracle);
    }

    function mintPolicy(
        address to,
        address stablecoin,
        uint256 coverage,
        uint256 durationSeconds,
        uint8 severity
    ) external onlyOwner returns (uint256 tokenId) {
        require(to != address(0), "To zero");
        require(stablecoin != address(0), "Stablecoin zero");
        require(coverage > 0, "Coverage zero");
        require(durationSeconds > 0, "Duration zero");
        require(severity < 3, "Bad severity");

        uint256 start = block.timestamp;
        uint256 expiry = start + durationSeconds;

        CoverNFT.Policy memory p = CoverNFT.Policy({
            stablecoin: stablecoin,
            coverage: coverage,
            start: start,
            expiry: expiry,
            severity: severity,
            isActive: true
        });

        tokenId = nft.mint(to, p);
    }

    function registerDepeg(address stablecoin, uint8 severity) external onlyOwner {
        require(stablecoin != address(0), "Stablecoin zero");
        require(severity < 3, "Bad severity");
        require(activeEventPlusOne[stablecoin][severity] == 0, "Active event exists");

        oracle.forceUpdate(stablecoin);

        (bool ok, uint256 minPrice) = oracle.getDepegStatus(stablecoin, severity);
        require(ok, "No depeg");

        uint256 tau = oracle.getThreshold(severity);
        require(tau > 0, "Tau zero");

        uint256 eventId = nextEventId;
        events[eventId] = DepegEvent({
            stablecoin: stablecoin,
            severity: severity,
            tau: tau,
            minPrice: minPrice,
            timestamp: block.timestamp,
            settled: false
        });

        activeEventPlusOne[stablecoin][severity] = eventId + 1;
        nextEventId++;
    }

    function settleEvent(uint256 eventId, uint256[] calldata tokenIds) external {
        DepegEvent storage e = events[eventId];
        require(!e.settled, "Already settled");
        require(tokenIds.length > 0, "Empty token list");
        require(e.tau > e.minPrice, "No payout band");

        uint256 totalRequired = 0;
        uint256 len = tokenIds.length;
        uint256[] memory payouts = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            CoverNFT.Policy memory p = nft.getPolicy(tokenIds[i]);
            if (
                p.stablecoin == e.stablecoin &&
                p.severity == e.severity &&
                p.isActive &&
                p.start <= e.timestamp &&
                p.expiry >= e.timestamp
            ) {
                uint256 payout = (p.coverage * (e.tau - e.minPrice)) / e.tau;
                payouts[i] = payout;
                totalRequired += payout;
            }
        }

        require(totalRequired > 0, "No eligible policies");

        uint256 poolBalance = pool.availableLiquidity();
        uint256 scale = totalRequired > poolBalance
            ? (poolBalance * 1e18) / totalRequired
            : 1e18;

        for (uint256 i = 0; i < len; i++) {
            if (payouts[i] == 0) continue;
            uint256 finalPay = (payouts[i] * scale) / 1e18;
            if (finalPay == 0) continue;
            address policyOwner = nft.ownerOf(tokenIds[i]);
            nft.markSettled(tokenIds[i]);
            pool.pay(policyOwner, finalPay);
        }

        e.settled = true;
        activeEventPlusOne[e.stablecoin][e.severity] = 0;
    }
}
