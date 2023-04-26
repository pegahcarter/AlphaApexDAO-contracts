// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Script.sol";

import { AlphaApexDAO } from "contracts/AlphaApexDAO.sol";
import { DividendTracker } from "contracts/DividendTracker.sol";
import { MultiRewards } from "contracts/MultiRewards.sol";
import { TokenStorage } from "contracts/TokenStorage.sol";

contract Deploy is Script {
    
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address publicKey = vm.addr(privateKey);
    address usdc = vm.envAddress("USDC");
    address router = vm.envAddress("ROUTER");
    address treasury = vm.envAddress("TREASURY");

    AlphaApexDAO public apex;
    DividendTracker public dividendTracker;
    MultiRewards public multiRewards;
    TokenStorage public tokenStorage;

    function run() public {
        vm.startBroadcast(privateKey);

        // Deploy AlphaApexDAO and DividendTracker
        apex = new AlphaApexDAO(usdc, router, treasury);

        // Get deployed DividendTracker address
        dividendTracker = apex.dividendTracker();
        
        // Deploy TokenStorage
        tokenStorage = new TokenStorage(usdc, address(apex), treasury, address(dividendTracker), router);
        apex.setTokenStorage(address(tokenStorage));

        // Deploy MultiRewards
        multiRewards = new MultiRewards(address(apex), usdc);
        apex.excludeFromFees(address(multiRewards), true);
        apex.setMultiRewardsAddress(address(multiRewards));

        vm.stopBroadcast();
    }
}