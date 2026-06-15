// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract CoverNFT is ERC721 {
    struct Policy {
        address stablecoin;
        uint256 coverage;
        uint256 start;
        uint256 expiry;
        uint8 severity;
        bool isActive;
    }

    uint256 public nextId;
    mapping(uint256 => Policy) public policies;
    address public core;

    modifier onlyCore() {
        require(msg.sender == core, "Not core");
        _;
    }

    constructor(address _core) ERC721("DepegGuard Cover", "DGC") {
        core = _core;
    }

    function setCore(address _core) external {
        require(core == address(0), "Core already set");
        require(_core != address(0), "Core is zero");
        core = _core;
    }

    function mint(address to, Policy calldata p) external onlyCore returns (uint256 id) {
        id = nextId++;
        policies[id] = p;
        _mint(to, id);
    }

    function markSettled(uint256 id) external onlyCore {
        policies[id].isActive = false;
    }

    function getPolicy(uint256 id) external view returns (Policy memory) {
        return policies[id];
    }
}
