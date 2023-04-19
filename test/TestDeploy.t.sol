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
    address usdc = vm.envAddress("USDC");
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

        deal(usdc, treasury, initialUSDCLiquidity);

        // impersonate the treasury and add initial liquidity
        vm.startPrank(treasury);
        IERC20(usdc).approve(address(router), initialUSDCLiquidity);
        d.apex().approve(address(router), initialAPEXLiquidity);
        
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
    }

    function testDeploy() public {
        // TODO: add validations here
        
    }

}