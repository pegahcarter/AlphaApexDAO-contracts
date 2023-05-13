pragma solidity ^0.8.0;

interface IRouter {
    struct route {
        address from;
        address to;
        bool stable;
    }
    function factory() external view returns (address);
    function getAmountsOut(
        uint256 amountIn,
        IRouter.route[] memory routes
    ) external view returns (uint256[] memory amounts);
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutmin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external;
}