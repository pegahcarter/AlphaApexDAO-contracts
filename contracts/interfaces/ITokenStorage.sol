// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenStorage {
    event SendDividends(uint256 tokensSwapped, uint256 amount);

    function swapTokensForWETH(uint256 tokens) external;

    function transferWETH(address to, uint256 amount) external;

    function addLiquidity(uint256 tokens, uint256 weths) external;

    function distributeDividends(
        uint256 swapTokensDividends,
        uint256 wethDividends
    ) external;

    function setLiquidityWallet(address _liquidityWallet) external;
    
    function addFee(bool isBuy, uint256 fee) external;
    function feesBuy() external view returns (uint256);
    function feesSell() external view returns (uint256);
}
