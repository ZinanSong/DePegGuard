// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract InsurancePool {
    using SafeERC20 for IERC20;

    IERC20 public immutable stablecoin;
    address public core;

    mapping(address => uint256) public lpBalance;

    modifier onlyCore() {
        require(msg.sender == core, "Not core");
        _;
    }

    constructor(address _stablecoin) {
        require(_stablecoin != address(0), "Stablecoin zero");
        stablecoin = IERC20(_stablecoin);
    }

    function setCore(address _core) external {
        require(core == address(0), "Core already set");
        require(_core != address(0), "Core is zero");
        core = _core;
    }

    function depositLiquidity(uint256 amount) external {
        require(amount > 0, "Amount 0");
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
        lpBalance[msg.sender] += amount;
    }

    function availableLiquidity() external view returns (uint256) {
        return stablecoin.balanceOf(address(this));
    }

    function pay(address to, uint256 amount) external onlyCore {
        require(to != address(0), "To zero");
        require(stablecoin.balanceOf(address(this)) >= amount, "Insufficient");
        stablecoin.safeTransfer(to, amount);
    }
}
