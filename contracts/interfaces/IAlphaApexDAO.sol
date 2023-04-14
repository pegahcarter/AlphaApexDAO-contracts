// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IAlphaApexDAO {
    event SwapAndAddLiquidity(
        uint256 tokensSwapped,
        uint256 usdcReceived,
        uint256 tokensIntoLiquidity
    );
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SetFee(
        uint256 _treasuryFee,
        uint256 _liquidityFee,
        uint256 _dividendFee
    );
    event SwapEnabled(bool enabled);
    event TaxEnabled(bool enabled);
    event CompoundingEnabled(bool enabled);
    event SetTokenStorage(address _tokenStorage);
    event UpdateDividendSettings(
        bool _swapEnabled,
        uint256 _swapTokensAtAmount,
        bool _swapAllToken
    );

    function claim() external;

    function withdrawableDividendOf(address account)
        external
        view
        returns (uint256);

    function triggerDividendDistribution() external;
}
