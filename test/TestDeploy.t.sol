// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { IRouter } from "contracts/interfaces/IRouter.sol";
import { IERC20 } from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestDeploy is Test {
    using stdJson for string;

    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address publicKey = vm.addr(privateKey);
    IERC20 weth = IERC20(vm.envAddress("WETH"));
    IRouter router = IRouter(vm.envAddress("ROUTER"));
    address treasury = vm.envAddress("TREASURY");
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 BLOCK_NUMBER = vm.envOr("BLOCK_NUMBER", uint256(0));

    Deploy public d;
    uint256 initialWETHLiquidity = 30 * 1e18;
    uint256 initialAPEXLiquidity = 5_000_000 * 1e18;
    // hardcoded into AlphaApexDAO
    uint256 swapTokensAtAmount = 10_000 * 1e18;

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, BLOCK_NUMBER);
        vm.selectFork(arbitrumFork);

        d = new Deploy();
        d.run();

        // add balances
        deal(address(weth), treasury, initialWETHLiquidity * 2);
        // deal(address(weth), alice, initialWETHLiquidity);
        // deal(address(weth), bob, initialWETHLiquidity);

        // impersonate the treasury and add initial liquidity
        vm.startPrank(d.apex().owner());
        d.apex().excludeFromFees(treasury, true);
        vm.stopPrank();
        
        vm.startPrank(treasury);
        IERC20(weth).approve(address(router), initialWETHLiquidity);
        d.apex().approve(address(router), initialAPEXLiquidity);

        router.addLiquidity(
            address(d.apex()),
            address(weth),
            false,
            initialAPEXLiquidity,
            initialWETHLiquidity,
            0,
            0,
            treasury,
            block.timestamp
        );
        vm.stopPrank();

        vm.startPrank(d.apex().owner());
        d.apex().excludeFromFees(treasury, false);
        vm.stopPrank();
    }

    function testInitialState() public {
        // Deploy AlphaApexDAO  
        assertEq(address(d.apex().weth()), address(weth));
        assertEq(address(d.apex().router()), address(router));
        assertEq(d.apex().treasury(), treasury);

        assertTrue(address(d.apex().pair()) != address(0));
        assertTrue(address(d.apex().dividendTracker()) != address(0));

        assertTrue(d.apex().automatedMarketMakerPairs(d.apex().pair()));
        assertTrue(d.dividendTracker().excludedFromDividends(d.apex().pair()));

        assertTrue(d.dividendTracker().excludedFromDividends(address(d.dividendTracker())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(d.apex())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(router)));
        assertTrue(d.dividendTracker().excludedFromDividends(treasury));
        assertTrue(d.dividendTracker().excludedFromDividends(d.apex().DEAD()));

        assertTrue(d.apex().isExcludedFromFees(address(d.apex())));
        assertTrue(d.apex().isExcludedFromFees(address(d.dividendTracker())));

        assertEq(d.apex().balanceOf(treasury), 1_000_000_000 * 1e18 - initialAPEXLiquidity);

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
        assertEq(d.dividendTracker().weth(), address(weth));
        assertEq(d.dividendTracker().apex(), address(d.apex()));
        assertEq(address(d.dividendTracker().router()), address(router));

        // Deploy TokenStorage
        assertTrue(address(d.tokenStorage()) != address(0));
        assertEq(d.tokenStorage().weth(), address(weth));
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
        assertEq(address(d.multiRewards().reflectionToken()), address(weth));
        assertTrue(d.apex().isExcludedFromFees(address(d.multiRewards())));
        assertEq(d.apex().multiRewards(), address(d.multiRewards()));
    }

    function testTransferHasNoFees() public {
        uint256 amount = 5 * 1e18;

        assertEq(d.apex().balanceOf(alice), 0);
        assertEq(d.apex().balanceOf(bob), 0);
        
        vm.startPrank(treasury);
        d.apex().transfer(alice, amount);
        vm.stopPrank();
        assertEq(d.apex().balanceOf(alice), amount);

        vm.startPrank(alice);
        d.apex().transfer(bob, amount);
        vm.stopPrank();
        assertEq(d.apex().balanceOf(bob), amount);
    }

    function _swap(address from, address input, address output, uint256 amount, address recipient) internal {
        IRouter.route[] memory routes = new IRouter.route[](1);
        routes[0] = IRouter.route(input, output, false);
        vm.startPrank(from);
        IERC20(input).approve(address(router), amount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            routes,
            recipient,
            block.timestamp + 1
        );
        vm.stopPrank();
    }

    function testBuyDoesNotTriggerDividendsBelowAmount() public {
        uint256 amount = 3 * 1e18;

        _swap(treasury, address(weth), address(d.apex()), amount, alice);

        // tokenStorage contains 2% of APEX bought from the 2% fee
        assertEq(d.apex().balanceOf(alice), 444441918617867697203910); // 444,441 APEX        
        assertEq(d.apex().balanceOf(address(d.apex().tokenStorage())), 9070243237099340759263); // 9,070 APEX

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        _swap(treasury, address(weth), address(d.apex()), amount, alice);

        assertGt(d.apex().balanceOf(address(d.apex().tokenStorage())), swapTokensAtAmount);
    }

    function testSellDoesNotTriggerDividendsBelowAmount() public {
        uint256 amountSwapped = swapTokensAtAmount * 8;
        uint256 fee = amountSwapped * 12 / 100;
        assertLt(fee, swapTokensAtAmount);

        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

        assertEq(d.apex().balanceOf(d.apex().pair()), initialAPEXLiquidity + amountSwapped - fee);
        assertEq(d.apex().balanceOf(address(d.apex().tokenStorage())), fee);

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);
        assertGt(d.apex().balanceOf(address(d.apex().tokenStorage())), swapTokensAtAmount);
    }

    function testBuyOnlyTriggerDividends() public {
        uint256 amountSwapped = 4 * 1e18;
        
        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);

        // Pre-calculations to be expected from the swap
        uint256 fee = d.apex().balanceOf(address(d.apex().tokenStorage()));
        assertGt(fee, swapTokensAtAmount);
        uint256 swapTokensTreasury = fee * d.apex().treasuryFeeBuyBPS() / d.apex().totalFeeBuyBPS();
        uint256 swapTokensDividends = fee * d.apex().dividendFeeBuyBPS() / d.apex().totalFeeBuyBPS();
        uint256 tokensForLiquidity = fee - swapTokensTreasury - swapTokensDividends;
        uint256 swapTokensTotal = swapTokensTreasury +
            swapTokensDividends +
            tokensForLiquidity / 2;

        uint256 wethSwapped;
        {
        IRouter.route[] memory routes = new IRouter.route[](1);
        routes[0] = IRouter.route(address(weth), address(d.apex()), false);
        uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, routes);
        wethSwapped = amounts[amounts.length - 1];
        }

        {
        uint256 wethTreasury = (wethSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 wethDividends = (wethSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 wethDividendTrackerBefore = weth.balanceOf(address(d.dividendTracker()));
        uint256 wethTreasuryBefore = weth.balanceOf(treasury);
        // uint256 wethPairBefore = weth.balanceOf(address(d.apex().pair()));
        // uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

        // Buy occurs - triggering the distribution
        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);

        // weth received by dividend tracker
        // assertEq(
        //     weth.balanceOf(address(d.dividendTracker())) - wethDividends,
        //     wethDividendTrackerBefore
        // );

        // weth received by treasury
        // assertEq(
        //     weth.balanceOf(treasury) - wethTreasury,
        //     wethTreasuryBefore
        // );

        // balance of apex in tokenStorage should only be the amountSwapped since it swapped out the prior amountSwapped
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            amountSwapped
        );

        // liquidity added to pair
        assertGt(
            weth.balanceOf(address(d.apex().pair())),
            initialWETHLiquidity + 2 * amountSwapped  // 0.2% fee
        );
        // assertGt(
        //     d.apex().balanceOf(address(d.apex().pair())),
        //     apexPairBefore
        // );
        }
    }

        function testSellOnlyTriggerDividends() public {
        // 12% fee on Sell - means at 100/12 * swapTokensAtAmount will distribute dividends
        // This rounds down from solidity so use 100/11 to distribute dividends
        uint256 amountSwapped = swapTokensAtAmount * 100 / 11;
        
        // sell
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

        // Pre-calculations to be expected from the swap
        uint256 swapTokensTreasury = swapTokensAtAmount * d.apex().treasuryFeeSellBPS() / d.apex().totalFeeSellBPS();
        uint256 swapTokensDividends = swapTokensAtAmount * d.apex().dividendFeeSellBPS() / d.apex().totalFeeSellBPS();
        uint256 tokensForLiquidity = swapTokensAtAmount - swapTokensTreasury - swapTokensDividends;
        uint256 swapTokensTotal = swapTokensTreasury +
            swapTokensDividends +
            tokensForLiquidity / 2;

        uint256 wethSwapped;
        {
        IRouter.route[] memory routes = new IRouter.route[](1);
        routes[0] = IRouter.route(address(weth), address(d.apex()), false);
        uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, routes);
        wethSwapped = amounts[amounts.length - 1];
        }

        {
        uint256 wethTreasury = (wethSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 wethDividends = (wethSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 wethDividendTrackerBefore = weth.balanceOf(address(d.dividendTracker()));
        uint256 wethTreasuryBefore = weth.balanceOf(treasury);
        uint256 wethPairBefore = weth.balanceOf(address(d.apex().pair()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

        // Sell occurs - triggering the distribution
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

        // weth received by dividend tracker
        assertEq(
            weth.balanceOf(address(d.dividendTracker())) - wethDividends,
            wethDividendTrackerBefore
        );

        // weth received by treasury
        assertEq(
            weth.balanceOf(treasury) - wethTreasury,
            wethTreasuryBefore
        );

        // balance of apex in tokenStorage should only be the amountSwapped since it swapped out the prior amountSwapped
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            amountSwapped
        );

        // liquidity added to pair
        assertGt(
            weth.balanceOf(address(d.apex().pair())),
            wethPairBefore
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pair())),
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
        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);
        // sell
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

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
        
        uint256 wethSwapped;
        {
        IRouter.route[] memory routes = new IRouter.route[](1);
        routes[0] = IRouter.route(address(weth), address(d.apex()), false);
        uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, routes);
        wethSwapped = amounts[amounts.length - 1];
        }

        {
        uint256 wethTreasury = (wethSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 wethDividends = (wethSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 wethDividendTrackerBefore = weth.balanceOf(address(d.dividendTracker()));
        uint256 wethTreasuryBefore = weth.balanceOf(treasury);
        uint256 wethPairBefore = weth.balanceOf(address(d.apex().pair()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

        // Sell occurs - triggering the distribution
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

        // weth received by dividend tracker
        assertEq(
            weth.balanceOf(address(d.dividendTracker())) - wethDividends,
            wethDividendTrackerBefore
        );

        // weth received by treasury
        assertEq(
            weth.balanceOf(treasury) - wethTreasury,
            wethTreasuryBefore
        );

        // balance of apex in tokenStorage should only be the amountSwapped since it swapped out the prior amountSwapped
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            amountSwapped
        );

        // liquidity added to pair
        assertGt(
            weth.balanceOf(address(d.apex().pair())),
            wethPairBefore
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pair())),
            apexPairBefore
        );
        }
    }

}