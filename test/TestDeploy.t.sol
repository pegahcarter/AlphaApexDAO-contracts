// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IPeripheryImmutableState } from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "contracts/interfaces/INonfungiblePositionManager.sol";
import { IERC20 } from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestDeploy is Test {
    using stdJson for string;

    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address publicKey = vm.addr(privateKey);
    IERC20 usdc = IERC20(vm.envAddress("USDC"));
    ISwapRouter router = ISwapRouter(vm.envAddress("ROUTER"));
    address treasury = vm.envAddress("TREASURY");
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 BLOCK_NUMBER = vm.envOr("BLOCK_NUMBER", uint256(0));

    INonfungiblePositionManager positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    Deploy public d;
    uint256 initialUSDCLiquidity = 50_000 * 1e6;
    uint256 initialAPEXLiquidity = 5_000_000 * 1e18;
    // hardcoded into AlphaApexDAO
    uint256 swapTokensAtAmount = 100_000 * 1e18;

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, BLOCK_NUMBER);
        vm.selectFork(arbitrumFork);

        d = new Deploy();
        d.run();
    
        vm.warp(1);
        vm.roll(1);

        // impersonate the treasury and add initial liquidity
        deal(address(usdc), treasury, initialUSDCLiquidity * 2);

        vm.startPrank(treasury);
        IERC20(usdc).approve(address(positionManager), type(uint256).max);
        IERC20(usdc).approve(address(d.apex().router()), type(uint256).max);
        d.apex().approve(address(positionManager), type(uint256).max);
        d.apex().approve(address(d.apex().router()), type(uint256).max);
        vm.stopPrank();
    }

    function _createAndInitPool() internal {
        vm.startPrank(d.apex().owner());
        d.apex().excludeFromFees(treasury, true);
        vm.stopPrank();
        
        // create and initialize pool
        address pool = IUniswapV3Factory(IPeripheryImmutableState(address(d.apex().router())).factory()).createPool(
                address(d.apex()),
                address(usdc),
                500 // low fee
            );
        IUniswapV3Pool(pool).initialize(1e20);
        
        vm.startPrank(d.apex().owner());
        d.apex().setPool(pool);
        vm.stopPrank();

        vm.startPrank(treasury);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(d.apex()),
            token1: address(usdc),
            fee: 500,
            tickLower: -50000, // from v3-core/TickMath
            tickUpper: 0,
            amount0Desired: initialAPEXLiquidity,
            amount1Desired: initialUSDCLiquidity,
            amount0Min: 0,
            amount1Min: 0,
            recipient: treasury,
            deadline: block.timestamp
        });

        positionManager.mint(params);
        vm.stopPrank();

        vm.startPrank(d.apex().owner());
        d.apex().excludeFromFees(treasury, false);
        vm.stopPrank();
    }

    function _swap(address from, address tokenIn, address tokenOut, uint256 amountIn, address recipient) internal {
        
        ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500, // set poolFee
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        vm.startPrank(from);
        router.exactInputSingle(params);
        vm.stopPrank();
    }

    function testInitialState() public {
        // Deploy AlphaApexDAO  
        assertEq(d.apex().owner(), publicKey);
        assertEq(address(d.apex().usdc()), address(usdc));
        assertEq(address(d.apex().router()), address(router));
        assertEq(d.apex().treasury(), treasury);
        assertEq(d.apex().lp(), publicKey);

        assertTrue(address(d.apex().pool()) == address(0));
        assertTrue(address(d.apex().dividendTracker()) != address(0));

        assertTrue(d.apex().automatedMarketMakerPools(d.apex().pool()));
        // assertTrue(d.dividendTracker().excludedFromDividends(d.apex().pool()));

        assertTrue(d.dividendTracker().excludedFromDividends(address(d.dividendTracker())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(d.apex())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(router)));
        assertTrue(d.dividendTracker().excludedFromDividends(treasury));
        assertTrue(d.dividendTracker().excludedFromDividends(d.apex().DEAD()));

        assertTrue(d.apex().isExcludedFromFees(address(d.apex())));
        assertTrue(d.apex().isExcludedFromFees(address(d.dividendTracker())));

        assertEq(d.apex().balanceOf(treasury), 1_000_000_000 * 1e18);

        assertEq(
            d.apex().totalFeeBuyBPS(),
            d.apex().treasuryFeeBuyBPS() + 
                d.apex().liquidityFeeBuyBPS() +
                d.apex().dividendFeeBuyBPS()
        );
        assertEq(d.apex().totalFeeBuyBPS(), 200);
        assertEq(
            d.apex().totalFeeSellBPS(),
            d.apex().treasuryFeeSellBPS() + 
                d.apex().liquidityFeeSellBPS() +
                d.apex().dividendFeeSellBPS()
        );
        assertEq(d.apex().totalFeeSellBPS(), 1200);

        // Deploy DividendTracker
        assertEq(d.dividendTracker().usdc(), address(usdc));
        assertEq(d.dividendTracker().apex(), address(d.apex()));
        assertEq(address(d.dividendTracker().router()), address(router));

        // Deploy TokenStorage
        assertTrue(address(d.tokenStorage()) != address(0));
        assertEq(d.tokenStorage().usdc(), address(usdc));
        assertEq(d.tokenStorage().apex(), address(d.apex()));
        assertEq(d.tokenStorage().liquidityWallet(), treasury);
        assertEq(address(d.tokenStorage().dividendTracker()), address(d.dividendTracker()));
        assertEq(address(d.tokenStorage().router()), address(router));
        // apex.setTokenStorage()
        assertEq(address(d.apex().tokenStorage()), address(d.tokenStorage()));
        assertTrue(d.dividendTracker().excludedFromDividends(address(d.tokenStorage())));
        assertTrue(d.apex().isExcludedFromFees(address(d.tokenStorage())));

        // Deploy MultiRewards
        assertTrue(address(d.multiRewards()) != address(0));
        assertEq(address(d.multiRewards().stakingToken()), address(d.apex()));
        assertEq(address(d.multiRewards().reflectionToken()), address(usdc));
        assertTrue(d.apex().isExcludedFromFees(address(d.multiRewards())));
        assertEq(d.apex().multiRewards(), address(d.multiRewards()));
    }

    function testTransferHasNoFees() public {
        uint256 amount = 5;

        assertEq(d.apex().balanceOf(alice), 0);
        assertEq(d.apex().balanceOf(bob), 0);

        vm.startPrank(treasury);
        d.apex().transfer(alice, amount);
        assertEq(d.apex().balanceOf(alice), amount);
        vm.stopPrank();

        vm.startPrank(alice);
        d.apex().transfer(bob, amount);
        assertEq(d.apex().balanceOf(bob), amount);
    }



    function testBuyDoesNotTriggerDividendsBelowAmount() public {
        _createAndInitPool();

        uint256 amountSwapped = 100 * 1e6;

        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        console.log(d.apex().balanceOf(alice));
        // assertEq(d.apex().balanceOf(alice), amountAfterSwap);
        // assertEq(d.apex().balanceOf(treasury), fee);

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        amountSwapped = 10_000 * 1e6;
        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        // assertEq(d.apex().balanceOf(alice), amountAfterSwap * 2);
        // assertEq(d.apex().balanceOf(treasury), fee * 2);
        // assertEq(d.tokenStorage().feesBuy(), fee);
    }

    function testSellDoesNotTriggerDividendsBelowAmount() public {
        // 12% fee on sell - means at 100/12 swapTokensAtAmount will distribute dividends
        uint256 fee = swapTokensAtAmount - 1;
        uint256 amountSwapped = fee * 100 / 12;
        uint256 amountAfterSwap = amountSwapped - fee;

        _swap(treasury, address(d.apex()), address(usdc), amountSwapped, alice);

        assertEq(d.apex().balanceOf(alice), amountAfterSwap);
        assertEq(d.apex().balanceOf(treasury), fee);

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        _swap(treasury, address(d.apex()), address(usdc), amountSwapped, alice);

        assertEq(d.apex().balanceOf(alice), amountAfterSwap * 2);
        assertEq(d.apex().balanceOf(treasury), fee * 2);
        assertEq(d.tokenStorage().feesSell(), fee);
    }

    function testBuyOnlyTriggerDividends() public {
        // 2% fee on buy - means at 100/2 swapTokensAtAmount will distribute dividends
        uint256 amountSwapped = swapTokensAtAmount * 100 / 2;
        
        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        // Pre-calculations to be expected from the swap
        uint256 swapTokensTreasury = swapTokensAtAmount * d.apex().treasuryFeeBuyBPS() / d.apex().totalFeeBuyBPS();
        uint256 swapTokensDividends = swapTokensAtAmount * d.apex().dividendFeeBuyBPS() / d.apex().totalFeeBuyBPS();
        uint256 tokensForLiquidity = swapTokensAtAmount - swapTokensTreasury - swapTokensDividends;
        
        uint256 swapTokensTotal = swapTokensAtAmount - tokensForLiquidity;
        uint256 usdcSwapped;
        {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(d.apex());
        // uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, path);
        // usdcSwapped = amounts[amounts.length - 1];
        usdcSwapped = 0;
        }

        {
        uint256 usdcTreasury = (usdcSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 usdcDividends = (usdcSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 usdcDividendTrackerBefore = usdc.balanceOf(address(d.dividendTracker()));
        uint256 usdcTreasuryBefore = usdc.balanceOf(treasury);
        uint256 usdcPairBefore = usdc.balanceOf(address(d.apex().pool()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pool()));

        // Buy occurs - triggering the distribution
        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        // usdc received by dividend tracker
        assertEq(
            usdc.balanceOf(address(d.dividendTracker())) - usdcDividends,
            usdcDividendTrackerBefore
        );

        // usdc received by treasury
        assertEq(
            usdc.balanceOf(treasury) - usdcTreasury,
            usdcTreasuryBefore
        );

        // balance of apex in tokenStorage should only be the amountSwapped since it swapped out the prior amountSwapped
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            amountSwapped
        );

        // liquidity added to pair
        assertGt(
            usdc.balanceOf(address(d.apex().pool())),
            usdcPairBefore
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pool())),
            apexPairBefore
        );
        }
    }

        function testSellOnlyTriggerDividends() public {
        // 12% fee on Sell - means at 100/12 * swapTokensAtAmount will distribute dividends
        // This rounds down from solidity so use 100/11 to distribute dividends
        uint256 amountSwapped = swapTokensAtAmount * 100 / 11;
        
        // sell
        _swap(treasury, address(d.apex()), address(usdc), amountSwapped, alice);

        // Pre-calculations to be expected from the swap
        uint256 swapTokensTreasury = swapTokensAtAmount * d.apex().treasuryFeeSellBPS() / d.apex().totalFeeSellBPS();
        uint256 swapTokensDividends = swapTokensAtAmount * d.apex().dividendFeeSellBPS() / d.apex().totalFeeSellBPS();
        uint256 tokensForLiquidity = swapTokensAtAmount - swapTokensTreasury - swapTokensDividends;
        uint256 swapTokensTotal = swapTokensTreasury +
            swapTokensDividends +
            tokensForLiquidity / 2;

        uint256 usdcSwapped;
        {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(d.apex());
        // uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, path);
        // usdcSwapped = amounts[amounts.length - 1];
        usdcSwapped = 0;
        }

        {
        uint256 usdcTreasury = (usdcSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 usdcDividends = (usdcSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 usdcDividendTrackerBefore = usdc.balanceOf(address(d.dividendTracker()));
        uint256 usdcTreasuryBefore = usdc.balanceOf(treasury);
        uint256 usdcPairBefore = usdc.balanceOf(address(d.apex().pool()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pool()));

        // Sell occurs - triggering the distribution
        _swap(treasury, address(d.apex()), address(usdc), amountSwapped, alice);

        // usdc received by dividend tracker
        assertEq(
            usdc.balanceOf(address(d.dividendTracker())) - usdcDividends,
            usdcDividendTrackerBefore
        );

        // usdc received by treasury
        assertEq(
            usdc.balanceOf(treasury) - usdcTreasury,
            usdcTreasuryBefore
        );

        // balance of apex in tokenStorage should only be the amountSwapped since it swapped out the prior amountSwapped
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            amountSwapped
        );

        // liquidity added to pair
        assertGt(
            usdc.balanceOf(address(d.apex().pool())),
            usdcPairBefore
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pool())),
            apexPairBefore
        );
        }
    }


    function testBuyAndSellTriggerDividends() public {
        // Don't trigger dividends until after a buy and sell occur to calculate the proportion of dividends correctly distributed
        // A 2% fee on buy means dividends distribute at 100/2 * swapTokensAtAmount or 50x.  For sake of rounding let's use 40x
        // as we know the dividends won't distribute until the third swap
        uint256 amountSwapped = swapTokensAtAmount * 40;

        // buy
        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);
        // sell
        _swap(treasury, address(d.apex()), address(usdc), amountSwapped, alice);

        uint256 swapTokensTreasury = 
            swapTokensAtAmount * d.apex().treasuryFeeBuyBPS() / d.apex().totalFeeBuyBPS() + 
            swapTokensAtAmount * d.apex().treasuryFeeSellBPS() / d.apex().totalFeeSellBPS();
        uint256 swapTokensDividends =
            swapTokensAtAmount * d.apex().dividendFeeBuyBPS() / d.apex().totalFeeBuyBPS() +
            swapTokensAtAmount * d.apex().dividendFeeSellBPS() / d.apex().totalFeeSellBPS();
        uint256 tokensForLiquidity = swapTokensAtAmount - swapTokensTreasury - swapTokensDividends;
        uint256 swapTokensTotal = swapTokensTreasury +
            swapTokensDividends +
            tokensForLiquidity / 2;
        
        uint256 usdcSwapped;
        {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(d.apex());
        // uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, path);
        // usdcSwapped = amounts[amounts.length - 1];
        usdcSwapped = 0;
        }

        {
        uint256 usdcTreasury = (usdcSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 usdcDividends = (usdcSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 usdcDividendTrackerBefore = usdc.balanceOf(address(d.dividendTracker()));
        uint256 usdcTreasuryBefore = usdc.balanceOf(treasury);
        uint256 usdcPairBefore = usdc.balanceOf(address(d.apex().pool()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pool()));

        // Sell occurs - triggering the distribution
        _swap(treasury, address(d.apex()), address(usdc), amountSwapped, alice);

        // usdc received by dividend tracker
        assertEq(
            usdc.balanceOf(address(d.dividendTracker())) - usdcDividends,
            usdcDividendTrackerBefore
        );

        // usdc received by treasury
        assertEq(
            usdc.balanceOf(treasury) - usdcTreasury,
            usdcTreasuryBefore
        );

        // balance of apex in tokenStorage should only be the amountSwapped since it swapped out the prior amountSwapped
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            amountSwapped
        );

        // liquidity added to pair
        assertGt(
            usdc.balanceOf(address(d.apex().pool())),
            usdcPairBefore
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pool())),
            apexPairBefore
        );
        }
    }
}