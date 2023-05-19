// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAlphaApexDAO {
    event SwapAndAddLiquidity(
        uint256 tokensSwapped,
        uint256 wethReceived,
        uint256 tokensIntoLiquidity
    );
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SetFee(
        uint256 _treasuryFeeBuy,
        uint256 _liquidityFeeBuy,
        uint256 _dividendFeeBuy,
        uint256 _treasuryFeeSell,
        uint256 _liquidityFeeSell,
        uint256 _dividendFeeSell
    );
    event SwapEnabled(bool enabled);
    event CompoundingEnabled(bool enabled);
    event SetTokenStorage(address _tokenStorage);
    event UpdateDividendSettings(
        uint256 _swapTokensAtAmount,
        bool _swapAllToken
    );

    function claim() external payable;

    function withdrawableDividendOf(address account)
        external
        view
        returns (uint256);

    function triggerDividendDistribution() external;
}
