// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface ITokenStorage {
    event SendDividends(uint256 tokensSwapped, uint256 amount);

    function swapTokensForUSDC(uint256 tokens) external;

    function transferUSDC(address to, uint256 amount) external;
    function transferAPEX(address to, uint256 amount) external;

    function distributeDividends(
        uint256 swapTokensDividends,
        uint256 usdcDividends
    ) external;

    function setLiquidityWallet(address _liquidityWallet) external;
    
    function addFee(bool isBuy, uint256 fee) external;
    function feesBuy() external view returns (uint256);
    function feesSell() external view returns (uint256);
}
