// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { ICamelotRouter } from "contracts/interfaces/ICamelotRouter.sol";
import { IERC20 } from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestDeploy is Test {
    using stdJson for string;

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

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(ARBITRUM_RPC_URL, BLOCK_NUMBER);
        vm.selectFork(arbitrumFork);

        d = new Deploy();
        d.run();

        // impersonate the treasury and add initial liquidity
        deal(usdc, treasury, initialUSDCLiquidity);

        vm.startPrank(treasury);
        IERC20(usdc).approve(address(router), initialUSDCLiquidity);
        d.apex().approve(address(router), initialAPEXLiquidity);

        d.apex().excludeFromFees(treasury, true);
        router.addLiquidity(
            address(d.apex()),
            usdc,
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

        assertTrue(d.apex().pair() != address(0));
        assertTrue(d.apex().dividendTracker() != address(0));

        assertTrue(d.apex().automatedMarketMakerPairs(d.apex().pair()));
        assertTrue(d.dividendTracker().excludedFromDividends(d.apex().pair()));

        assertTrue(d.dividendTracker().excludedFromDividends(address(d.dividendTracker())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(d.apex())));
        assertTrue(d.dividendTracker().excludedFromDividends(address(router)));
        assertTrue(d.dividendTracker().excludedFromDividends(treasury));
        assertTrue(d.dividendTracker().excludedFromDividends(d.apex().DEAD()));

        assertTrue(d.apex().isExcludedFromFees(address(d.apex())));
        assertTrue(d.apex().isExcludedFromFees(address(d.dividendTracker())));

        assertTrue(d.apex().balanceOf(treasury), 1_000_000_000 * 1e18);

        assertEq(
            d.apex().totalFeeBuyBPS(),
            d.apex().treasuryFeeBuyBPS() + 
                d.apex().liquidityFeeBuyBPS() +
                d.apex().dividendFeeBuyBPS()
        );
        assertEq(
            d.apex().totalFeeSellBPS(),
            d.apex().treasuryFeeSellBPS() + 
                d.apex().liquidityFeeSellBPS() +
                d.apex().dividendFeeSellBPS()
        );

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
        assertEq(address(d.apex().tokenStorage()), d.tokenStorage());
        assertTrue(d.dividendTracker().excludedFromDividends(address(d.tokenStorage())));
        assertTrue(d.apex().isExcludedFromFees(address(d.tokenStorage)));

        // Deploy MultiRewards
        assertTrue(address(d.multiRewards()) != address(0));
        assertEq(address(d.multiRewards().stakingToken()), d.apex());
        assertEq(address(d.multiRewards().reflectionToken()), address(usdc));
        assertTrue(d.apex().isExcludedFromFees(address(d.multiRewards())));
        assertEq(d.apex().multiRewards(), address(d.multiRewards()));
    }

    function testBuyLessThanSwapTrigger() public {

    }

    function testTransferHasNoFees() public {

    }


}