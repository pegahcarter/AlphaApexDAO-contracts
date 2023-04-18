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
    address usdc = vm.envAddress("USDC"); // TODO
    address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");
    address treasury = vm.envAddress("TREASURY"); // TODO

    AlphaApexDAO public apex;
    DividendTracker public dividendTracker;
    MultiRewards public multiRewards;
    TokenStorage public tokenStorage;

    function run() public {
        vm.startBroadcast(privateKey);

        // Deploy AlphaApexDAO
        apex = new AlphaApexDAO(usdc, uniswapRouter, treasury);

        // Deploy TokenStorage
        dividendTracker = apex.dividendTracker();
        tokenStorage = new TokenStorage(usdc, address(apex), publicKey, address(dividendTracker), uniswapRouter);
        apex.setTokenStorage(address(tokenStorage));

        // Deploy MultiRewards
        multiRewards = new MultiRewards(publicKey, address(apex), usdc);

        // Apex related managed
        apex.excludeFromFees(address(multiRewards), true);
        apex.setMultiRewardsAddress(address(multiRewards));
        apex.updateDividendSettings(true, 1000, true);

        vm.stopBroadcast();
    }
}