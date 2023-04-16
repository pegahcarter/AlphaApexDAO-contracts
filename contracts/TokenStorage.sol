// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { IERC20} from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20} from  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Router02} from  "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import { IDividendTracker} from  "./interfaces/IDividendTracker.sol";
import { ITokenStorage} from  "./interfaces/ITokenStorage.sol";

contract TokenStorage is ITokenStorage {
    using SafeERC20 for IERC20;

    /* ============ State ============ */

    IDividendTracker public immutable dividendTracker;
    IUniswapV2Router02 public uniswapV2Router;

    address public immutable usdc;
    address public immutable tokenAddress;
    address public liquidityWallet;

    constructor(
        address _usdc,
        address _tokenAddress,
        address _liquidityWallet,
        address _dividendTracker,
        address _uniswapRouter
    ) {
        require(_usdc != address(0), "USDC address zero");
        require(_tokenAddress != address(0), "Token address zero");
        require(
            _liquidityWallet != address(0),
            "Liquidity wallet address zero"
        );
        require(
            _dividendTracker != address(0),
            "Dividend tracker address zero"
        );
        require(_uniswapRouter != address(0), "Uniswap router address zero");

        usdc = _usdc;
        tokenAddress = _tokenAddress;
        liquidityWallet = _liquidityWallet;
        dividendTracker = IDividendTracker(_dividendTracker);
        uniswapV2Router = IUniswapV2Router02(_uniswapRouter);
    }

    /* ============ External Functions ============ */

    function transferUSDC(address to, uint256 amount) external {
        require(
            msg.sender == tokenAddress,
            "This address is not allowed to interact with the contract"
        );
        IERC20(usdc).safeTransfer(to, amount);
    }

    function swapTokensForUSDC(uint256 tokens) external {
        require(
            msg.sender == tokenAddress,
            "This address is not allowed to interact with the contract"
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenAddress);
        path[1] = usdc;

        IERC20(tokenAddress).approve(address(uniswapV2Router), tokens);
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokens,
            0, // accept any amount of usdc
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokens, uint256 usdcs) external {
        require(
            msg.sender == tokenAddress,
            "This address is not allowed to interact with the contract"
        );
        IERC20(tokenAddress).approve(address(uniswapV2Router), tokens);
        IERC20(usdc).approve(address(uniswapV2Router), usdcs);

        uniswapV2Router.addLiquidity(
            address(tokenAddress),
            usdc,
            tokens,
            usdcs,
            0, // slippage unavoidable
            0, // slippage unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    function distributeDividends(
        uint256 swapTokensDividends,
        uint256 usdcDividends
    ) external {
        require(
            msg.sender == tokenAddress,
            "This address is not allowed to interact with the contract"
        );
        IERC20(usdc).approve(address(dividendTracker), usdcDividends);
        try dividendTracker.distributeDividends(usdcDividends) {
            emit SendDividends(swapTokensDividends, usdcDividends);
        } catch Error(
            string memory /*err*/
        ) {}
    }

    function setLiquidityWallet(address _liquidityWallet) external {
        require(
            msg.sender == tokenAddress,
            "This address is not allowed to interact with the contract"
        );
        require(_liquidityWallet != address(0), "Digits: zero!");

        liquidityWallet = _liquidityWallet;
    }
}
