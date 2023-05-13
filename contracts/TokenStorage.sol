// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { IERC20 } from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRouter } from "./interfaces/IRouter.sol";

import { IDividendTracker } from  "./interfaces/IDividendTracker.sol";
import { ITokenStorage } from  "./interfaces/ITokenStorage.sol";

contract TokenStorage is ITokenStorage {
    using SafeERC20 for IERC20;

    /* ============ State ============ */

    IDividendTracker public immutable dividendTracker;
    IRouter public router;

    address public immutable weth;
    address public immutable apex;
    address public liquidityWallet;

    uint256 public feesBuy;
    uint256 public feesSell;

    constructor(
        address _weth,
        address _apex,
        address _liquidityWallet,
        address _dividendTracker,
        address _router
    ) {
        require(_weth != address(0), "WETH address zero");
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

        weth = _weth;
        apex = _apex;
        liquidityWallet = _liquidityWallet;
        dividendTracker = IDividendTracker(_dividendTracker);
        router = IRouter(_router);
    }

    /* ============ External Functions ============ */

    function transferWETH(address to, uint256 amount) external {
        require(msg.sender == apex, "!apex");
        IERC20(weth).safeTransfer(to, amount);
    }

    function swapTokensForWETH(uint256 tokens) external {
        require(msg.sender == apex, "!apex");
        IRouter.route[] memory routes = new IRouter.route[](1);
        routes[0] = IRouter.route(apex, weth, false);

        IERC20(apex).approve(address(router), tokens);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokens,
            0, // accept any amount of weth
            routes,
            address(this),
            block.timestamp
        );

        // Now that tokens have been swapped - reset fee accrual
        feesBuy = 0;
        feesSell = 0;
    }

    function addLiquidity(uint256 tokens, uint256 weths) external {
        require(msg.sender == apex, "!apex");
        IERC20(apex).approve(address(router), tokens);
        IERC20(weth).approve(address(router), weths);

        router.addLiquidity(
            apex,
            weth,
            false, // stable
            tokens,
            weths,
            0, // slippage unavoidable
            0, // slippage unavoidable
            liquidityWallet,
            block.timestamp
        );
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
        uint256 wethDividends
    ) external {
        require(msg.sender == apex, "!apex");
        IERC20(weth).approve(address(dividendTracker), wethDividends);
        try dividendTracker.distributeDividends(wethDividends) {
            emit SendDividends(swapTokensDividends, wethDividends);
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
