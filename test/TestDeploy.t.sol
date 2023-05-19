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

        vm.label(publicKey, "Deployer");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(treasury, "Treasury");
        vm.label(address(weth), "WETH");
        vm.label(address(router), "Router");
        vm.label(address(d.apex()), "APEX");
        vm.label(d.apex().pair(), "APEX/WETH LP");
        vm.label(address(d.apex().tokenStorage()), "TokenStorage");
        vm.label(address(d.apex().dividendTracker()), "DividendTracker");
    }

    function testInitialState() public {
        // Deploy AlphaApexDAO  
        assertEq(address(d.apex().weth()), address(weth));
        assertEq(address(d.apex().router()), address(router));
        assertEq(d.apex().treasury(), treasury);
        assertEq(d.apex().owner(), publicKey);

        assertTrue(address(d.apex().pair()) != address(0));
        assertTrue(address(d.apex().dividendTracker()) != address(0));

        assertTrue(d.apex().automatedMarketMakerPairs(d.apex().pair()));
        assertTrue(d.dividendTracker().excludedFromDividends(d.apex().pair()));

        assertTrue(d.dividendTracker().excludedFromDividends(address(d.dividendTracker())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(d.apex())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(router)));

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
        uint256 amountSwapped = 3 * 1e18;

        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);

        // tokenStorage contains 2% of APEX bought from the 2% fee
        assertEq(d.apex().balanceOf(alice), 444441918617867697203910); // 444,441 APEX        
        assertEq(d.apex().balanceOf(address(d.apex().tokenStorage())), 9070243237099340759263); // 9,070 APEX

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);

        assertGt(d.apex().balanceOf(address(d.apex().tokenStorage())), swapTokensAtAmount);
    }

    function testSellDoesNotTriggerDividendsBelowAmount() public {
        uint256 amountSwapped = swapTokensAtAmount * 8;
        uint256 dexFee = amountSwapped * 22 / 10_000;
        uint256 fee = amountSwapped * 12 / 100;
        assertLt(fee, swapTokensAtAmount);

        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

        assertEq(d.apex().balanceOf(d.apex().pair()), initialAPEXLiquidity + amountSwapped - dexFee - fee);
        assertApproxEqAbs(d.apex().balanceOf(address(d.apex().tokenStorage())) * 1e18 / fee, 1e18, 1e15); // 99.9% precision

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);
        assertGt(d.apex().balanceOf(address(d.apex().tokenStorage())), swapTokensAtAmount);
    }

    function testBuyOnlyTriggerDividends() public {
        uint256 amountSwapped = 5 * 1e18;
        
        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);

        // Assert that tokenStorage will swap because tokens accrued have exceeded swapTokensAtAmount
        uint256 apexBalanceStorage = d.apex().balanceOf(address(d.apex().tokenStorage()));
        assertGt(apexBalanceStorage, swapTokensAtAmount);
        assertEq(d.apex().tokenStorage().feesBuy(), apexBalanceStorage);

        uint256 swapTokensTreasury = apexBalanceStorage * d.apex().treasuryFeeBuyBPS() /
            d.apex().totalFeeBuyBPS();
        uint256 swapTokensDividends = apexBalanceStorage * d.apex().dividendFeeBuyBPS() / 
            d.apex().totalFeeBuyBPS();
        
        uint256 swapTokensLiquidity = (apexBalanceStorage - swapTokensTreasury - swapTokensDividends) / 2;
        uint256 swapTokensTotal = swapTokensTreasury + swapTokensDividends + swapTokensLiquidity;

        uint256 wethSwapped;
        {
            IRouter.route[] memory routes = new IRouter.route[](1);
            routes[0] = IRouter.route(address(d.apex()), address(weth), false);
            uint256[] memory amounts = router.getAmountsOut(swapTokensTotal, routes);
            wethSwapped = amounts[amounts.length - 1];
        }

        uint256 wethForTreasury = (wethSwapped * swapTokensTreasury) / swapTokensTotal;
        uint256 wethForDividends = (wethSwapped * swapTokensDividends) / swapTokensTotal;

        uint256 wethTreasuryBefore = weth.balanceOf(treasury);
        uint256 wethPairBefore = weth.balanceOf(address(d.apex().pair()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

        // transfer occurs - triggering the distribution
        vm.startPrank(alice);
        d.apex().transfer(bob, d.apex().balanceOf(alice));
        vm.stopPrank();

        assertEq(d.apex().tokenStorage().feesBuy(), 0);

        // weth received by dividend tracker
        assertApproxEqAbs(
            1e18 * weth.balanceOf(address(d.dividendTracker())) / wethForDividends,
            1e18,
            1e15 // 99.9% accurate
        );

        // weth received by treasury
        assertApproxEqAbs(
            1e18 * (weth.balanceOf(treasury) - wethForTreasury) / wethTreasuryBefore,
            1e18,
            1e12 // 99.9999% accurate
        );

        // Token storage should have cleared out APEX into WETH
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            0
        );

        // liquidity added to pair
        assertGt(
            weth.balanceOf(address(d.apex().pair())),
            wethPairBefore - wethSwapped
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pair())),
            apexPairBefore + swapTokensTotal
        );
    }

    function testSellOnlyTriggerDividends() public {
        // 12% fee on Sell - means at 100/12 * swapTokensAtAmount will distribute dividends
        // This rounds down so use 100/11 to distribute dividends
        uint256 amountSwapped = swapTokensAtAmount * 100 / 11;
        
        // sell
        _swap(treasury, address(d.apex()), address(weth), amountSwapped, alice);

        // Assert that tokenStorage will swap because tokens accrued have exceeded swapTokensAtAmount
        uint256 apexBalanceStorage = d.apex().balanceOf(address(d.apex().tokenStorage()));
        assertGt(apexBalanceStorage, swapTokensAtAmount);
        assertApproxEqAbs(
            1e18 * d.apex().tokenStorage().feesSell() / apexBalanceStorage,
            1e18,
            1e15 // 99.9% accurate
        );

        uint256 swapTokensTreasury = apexBalanceStorage * d.apex().treasuryFeeSellBPS() /
            d.apex().totalFeeSellBPS();
        uint256 swapTokensDividends = apexBalanceStorage * d.apex().dividendFeeSellBPS() / 
            d.apex().totalFeeSellBPS();
        
        uint256 swapTokensLiquidity = (apexBalanceStorage - swapTokensTreasury - swapTokensDividends) / 2;
        uint256 swapTokensTotal = swapTokensTreasury + swapTokensDividends + swapTokensLiquidity;

        uint256 wethSwapped;
        {
            IRouter.route[] memory routes = new IRouter.route[](1);
            routes[0] = IRouter.route(address(d.apex()), address(weth), false);
            uint256[] memory amounts = router.getAmountsOut(swapTokensTotal, routes);
            wethSwapped = amounts[amounts.length - 1];
        }

        uint256 wethForTreasury = (wethSwapped * swapTokensTreasury) / swapTokensTotal;
        uint256 wethForDividends = (wethSwapped * swapTokensDividends) / swapTokensTotal;
        
        uint256 wethTreasuryBefore = weth.balanceOf(treasury);
        uint256 wethPairBefore = weth.balanceOf(address(d.apex().pair()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

        // transfer occurs - triggering the distribution
        vm.startPrank(treasury);
        d.apex().transfer(bob, d.apex().balanceOf(treasury));
        vm.stopPrank();

        assertEq(d.apex().tokenStorage().feesSell(), 0);

        // weth received by dividend tracker
        assertApproxEqAbs(
            1e18 * weth.balanceOf(address(d.dividendTracker())) / wethForDividends,
            1e18,
            1e14 // 99.99% accurate
        );

        // weth received by treasury
        assertApproxEqAbs(
            1e18 * (weth.balanceOf(treasury) - wethForTreasury) / wethTreasuryBefore,
            1e18,
            1e12 // 99.9999% accurate
        );

        // Token storage should have cleared out APEX into WETH
        // Math is 99.99% efficient: from > 10k APEX to <1 APEX
        assertLt(
            d.apex().balanceOf(address(d.tokenStorage())),
            1e18
        );

        // liquidity added to pair
        assertGt(
            weth.balanceOf(address(d.apex().pair())),
            wethPairBefore - wethSwapped
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pair())),
            apexPairBefore + swapTokensTotal
        );
    }


    function testBuyAndSellTriggerDividends() public {
        // buy (does not trigger - see testBuyDoesNotTrigger)
        _swap(treasury, address(weth), address(d.apex()), 3 * 1e18, alice);
        // sell
        _swap(treasury, address(d.apex()), address(weth), swapTokensAtAmount * 8, alice);

        // Assert that tokenStorage will swap because tokens accrued have exceeded swapTokensAtAmount
        uint256 apexBalanceStorage = d.apex().balanceOf(address(d.apex().tokenStorage()));
        assertGt(apexBalanceStorage, swapTokensAtAmount);

        uint256 swapTokensTreasury;
        uint256 swapTokensDividends;
        uint256 swapTokensLiquidity;
        uint256 swapTokensTotal;
        {
            uint256 feesBuy = d.apex().tokenStorage().feesBuy();
            uint256 feesSell = d.apex().tokenStorage().feesSell();
            uint256 buyToSellRatio = 1e18 * feesBuy / (feesBuy + feesSell);
            uint256 sellToBuyRatio = 1e18 - buyToSellRatio;

            swapTokensTreasury = 
                apexBalanceStorage * d.apex().treasuryFeeBuyBPS() / d.apex().totalFeeBuyBPS() * buyToSellRatio / 1e18 +
                apexBalanceStorage * d.apex().treasuryFeeSellBPS() / d.apex().totalFeeSellBPS() * sellToBuyRatio / 1e18;
            swapTokensDividends =
                apexBalanceStorage * d.apex().dividendFeeBuyBPS() / d.apex().totalFeeBuyBPS() * buyToSellRatio / 1e18 +
                apexBalanceStorage * d.apex().dividendFeeSellBPS() / d.apex().totalFeeSellBPS() * sellToBuyRatio / 1e18;
            swapTokensLiquidity = (apexBalanceStorage - swapTokensTreasury - swapTokensDividends) / 2;
            swapTokensTotal = swapTokensTreasury +
                swapTokensDividends +
                swapTokensLiquidity;
                
        }

        uint256 wethSwapped;
        {
            IRouter.route[] memory routes = new IRouter.route[](1);
            routes[0] = IRouter.route(address(d.apex()), address(weth), false);
            uint256[] memory amounts = router.getAmountsOut(swapTokensTotal, routes);
            wethSwapped = amounts[amounts.length - 1];
        }

        uint256 wethForTreasury = (wethSwapped * swapTokensTreasury) / swapTokensTotal;
        uint256 wethForDividends = (wethSwapped * swapTokensDividends) / swapTokensTotal;

        uint256 wethTreasuryBefore = weth.balanceOf(treasury);
        uint256 wethPairBefore = weth.balanceOf(address(d.apex().pair()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

        // transfer occurs - triggering the distribution
        vm.startPrank(alice);
        d.apex().transfer(bob, d.apex().balanceOf(alice));
        vm.stopPrank();

        // weth received by dividend tracker
        assertApproxEqAbs(
            1e18 * weth.balanceOf(address(d.dividendTracker())) / wethForDividends,
            1e18,
            1e15 // 99.9% accurate
        );

        // weth received by treasury
        assertApproxEqAbs(
            1e18 * (weth.balanceOf(treasury) - wethForTreasury) / wethTreasuryBefore,
            1e18,
            1e12 // 99.9999% accurate
        );

        // Token storage should have cleared out APEX into WETH
        assertEq(
            d.apex().balanceOf(address(d.tokenStorage())),
            0
        );

        // liquidity added to pair
        assertGt(
            weth.balanceOf(address(d.apex().pair())),
            wethPairBefore - wethSwapped
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pair())),
            apexPairBefore + swapTokensTotal
        );
    }

    function testClaimDividends() public {
        uint256 amountSwapped = 5 * 1e18;        
        _swap(treasury, address(weth), address(d.apex()), amountSwapped, alice);

        vm.startPrank(treasury);
        d.apex().transfer(bob, 1e18);

        uint256 dividendsAvailable = weth.balanceOf(address(d.apex().dividendTracker()));
        console.log(dividendsAvailable);
        // pct of dividends
        uint256 totalSupplyEligible = d.apex().balanceOf(treasury) + d.apex().balanceOf(alice) + d.apex().balanceOf(bob);
        uint256 dividendsTreasury = dividendsAvailable * d.apex().balanceOf(treasury) / totalSupplyEligible;
        uint256 dividendsAlice = dividendsAvailable * d.apex().balanceOf(alice) / totalSupplyEligible;

        uint256 ethBeforeTreasury = treasury.balance;
        uint256 ethBeforeAlice = alice.balance;

        d.apex().claim();
        vm.stopPrank();

        vm.startPrank(alice);
        d.apex().claim();
        vm.stopPrank();

        assertApproxEqAbs(
            1e18 * treasury.balance / (ethBeforeTreasury + dividendsTreasury),
            1e18,
            1e7 // 99.99999999999% accurate
        );
        assertEq(alice.balance, ethBeforeAlice + dividendsAlice);
    }

}