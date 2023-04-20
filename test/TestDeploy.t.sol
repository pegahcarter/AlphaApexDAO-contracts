// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { ICamelotRouter } from "contracts/interfaces/ICamelotRouter.sol";
import { IERC20 } from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestDeploy is Test {
    using stdJson for string;

    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address publicKey = vm.addr(privateKey);
    IERC20 usdc = IERC20(vm.envAddress("USDC"));
    ICamelotRouter router = ICamelotRouter(vm.envAddress("ROUTER"));
    address treasury = vm.envAddress("TREASURY");
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    uint256 BLOCK_NUMBER = vm.envOr("BLOCK_NUMBER", uint256(0));

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

        // impersonate the treasury and add initial liquidity
        deal(address(usdc), treasury, initialUSDCLiquidity);

        vm.startPrank(treasury);
        IERC20(usdc).approve(address(router), initialUSDCLiquidity);
        d.apex().approve(address(router), initialAPEXLiquidity);

        d.apex().excludeFromFees(treasury, true);
        router.addLiquidity(
            address(d.apex()),
            address(usdc),
            initialAPEXLiquidity,
            initialUSDCLiquidity,
            0,
            0,
            treasury,
            block.timestamp
        );
        d.apex().excludeFromFees(treasury, false);
    }

    function testInitialState() public {
        // Deploy AlphaApexDAO  
        assertEq(address(d.apex().usdc()), address(usdc));
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
        uint256 amount = 5 * 1e18;

        assertEq(d.apex().balanceOf(alice), 0);
        assertEq(d.apex().balanceOf(bob), 0);
        
        vm.prank(treasury);
        d.apex().transfer(alice, amount);
        assertEq(d.apex().balanceOf(alice), amount);

        vm.prank(alice);
        d.apex().transfer(bob, amount);
        assertEq(d.apex().balanceOf(bob), amount);
    }

    function _swap(address from, address input, address output, uint256 amount, address recipient) internal {
        address[] memory path = new address[](2);
        path[0] = input;
        path[1] = output;
        vm.prank(from);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            recipient,
            address(0),
            block.timestamp + 1
        );
    }

    function testBuyDoesNotTriggerSwapBelowAmount() public {
        // 2% fee on buy - means at 100/2 swapTokensAtAmount will trigger swap
        uint256 fee = swapTokensAtAmount - 1;
        uint256 amountSwapped = fee * 100 / 2;
        uint256 amountAfterSwap = amountSwapped - fee;

        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        assertEq(d.apex().balanceOf(alice), amountAfterSwap);
        assertEq(d.apex().balanceOf(treasury), fee);

        // swap only happens after swapTokensAtAmount is high enough - which will only happen
        // after the execution of a second swap
        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        assertEq(d.apex().balanceOf(alice), amountAfterSwap * 2);
        assertEq(d.apex().balanceOf(treasury), fee * 2);
        assertEq(d.tokenStorage().feesBuy(), fee);
    }

    function testSellDoesNotTriggerSwapBelowAmount() public {
        // 12% fee on sell - means at 100/12 swapTokensAtAmount will trigger swap
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

    function testBuyOnlyTriggerSwap() public {
        // 2% fee on buy - means at 100/2 swapTokensAtAmount will trigger swap
        uint256 amountSwapped = swapTokensAtAmount * 100 / 2;
        
        _swap(treasury, address(usdc), address(d.apex()), amountSwapped, alice);

        // Pre-calculations to be expected from the swap
        uint256 swapTokensTreasury = swapTokensAtAmount * d.apex().treasuryFeeBuyBPS() / d.apex().totalFeeBuyBPS();
        uint256 swapTokensDividends = swapTokensAtAmount * d.apex().dividendFeeBuyBPS() / d.apex().totalFeeBuyBPS();
        uint256 tokensForLiquidity = swapTokensAtAmount - swapTokensTreasury - swapTokensDividends;
        uint256 swapTokensTotal = swapTokensTreasury +
            swapTokensDividends +
            tokensForLiquidity / 2;

        uint256 usdcSwapped;
        {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(d.apex());
        uint256[] memory amounts = router.getAmountsOut(swapTokensAtAmount, path);
        usdcSwapped = amounts[amounts.length - 1];
        }

        {
        uint256 usdcTreasury = (usdcSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 usdcDividends = (usdcSwapped * swapTokensDividends) /
            swapTokensTotal;

        uint256 usdcDividendTrackerBefore = usdc.balanceOf(address(d.dividendTracker()));
        uint256 usdcTreasuryBefore = usdc.balanceOf(treasury);
        uint256 usdcPairBefore = usdc.balanceOf(address(d.apex().pair()));
        uint256 apexPairBefore = d.apex().balanceOf(address(d.apex().pair()));

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
            usdc.balanceOf(address(d.apex().pair())),
            usdcPairBefore
        );
        assertGt(
            d.apex().balanceOf(address(d.apex().pair())),
            apexPairBefore
        );
        }
    }
}