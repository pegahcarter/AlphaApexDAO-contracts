// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { IERC20 } from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { IDividendTracker } from  "./interfaces/IDividendTracker.sol";
import { ITokenStorage } from  "./interfaces/ITokenStorage.sol";

contract TokenStorage is ITokenStorage {
    using SafeERC20 for IERC20;

    /* ============ State ============ */

    IDividendTracker public immutable dividendTracker;
    ISwapRouter public router;

    address public immutable usdc;
    address public immutable apex;
    address public liquidityWallet;

    uint256 public feesBuy;
    uint256 public feesSell;

    constructor(
        address _usdc,
        address _apex,
        address _liquidityWallet,
        address _dividendTracker,
        address _router
    ) {
        require(_usdc != address(0), "USDC address zero");
        require(_apex != address(0), "Apex address zero");
        require(
            _liquidityWallet != address(0),
            "Liquidity wallet address zero"
        );
        require(
            _dividendTracker != address(0),
            "Dividend tracker address zero"
        );
        require(_router != address(0), "Uniswap router address zero");

        usdc = _usdc;
        apex = _apex;
        liquidityWallet = _liquidityWallet;
        dividendTracker = IDividendTracker(_dividendTracker);
        router = ISwapRouter(_router);
    }

    /* ============ External Functions ============ */

    function transferUSDC(address to, uint256 amount) external {
        require(msg.sender == apex, "!apex");
        IERC20(usdc).safeTransfer(to, amount);
    }

    function transferAPEX(address to, uint256 amount) external {
        require(msg.sender == apex, "!apex");
        IERC20(apex).safeTransfer(to, amount);
    }

    function swapTokensForUSDC(uint256 tokens) external {
        require(msg.sender == apex, "!apex");
        address[] memory path = new address[](2);
        path[0] = apex;
        path[1] = usdc;

        IERC20(apex).approve(address(router), tokens);

        ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: apex,
                tokenOut: usdc,
                fee: 500, // set poolFee
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: tokens,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(params);

        // Now that tokens have been swapped - reset fee accrual
        feesBuy = 0;
        feesSell = 0;
    }

    function addFee(bool isBuy, uint256 fee) external {
        require(msg.sender == apex, "!apex");
        if (isBuy) {
            feesBuy += fee;
        } else {
            feesSell += fee;
        }
    }

    function distributeDividends(
        uint256 swapTokensDividends,
        uint256 usdcDividends
    ) external {
        require(msg.sender == apex, "!apex");
        IERC20(usdc).approve(address(dividendTracker), usdcDividends);
        try dividendTracker.distributeDividends(usdcDividends) {
            emit SendDividends(swapTokensDividends, usdcDividends);
        } catch Error(
            string memory /*err*/
        ) {}
    }

    function setLiquidityWallet(address _liquidityWallet) external {
        require(msg.sender == apex, "!apex");
        require(_liquidityWallet != address(0), "Digits: zero!");

        liquidityWallet = _liquidityWallet;
    }
}
