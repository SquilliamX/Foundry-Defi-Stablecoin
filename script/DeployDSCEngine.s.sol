// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// Import necessary contracts
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    // Declaring Arrays to store allowed collateral token addresses and their corresponding price feeds
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        // Create new instance of HelperConfig to get network-specific addresses
        // This will either return mock addresses for local testing or real addresses for testnet
        HelperConfig config = new HelperConfig();

        // Get all the network configuration values using the destructuring syntax
        // wethUsdPriceFeed: Price feed for ETH/USD
        // wbtcUsdPriceFeed: Price feed for BTC/USD
        // weth: WETH token address
        // wbtc: WBTC token address
        // deployerKey: Private key for deployment (different for local vs testnet)
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        // Set up our arrays with the token addresses and their corresponding price feeds
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        // Start broadcasting our transactions
        vm.startBroadcast();

        // Deploy the DecentralizedStableCoin (DSC) token contract
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();

        // Deploy the DSCEngine contract, passing in:
        // 1. Array of allowed collateral token addresses
        // 2. Array of price feeds for those tokens
        // 3. Address of the DSC token contract
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // Transfer ownership of the DSC contract to the engine
        // This ensures only the engine can mint/burn DSC tokens
        // This is a critical security feature
        dsc.transferOwnership(address(engine));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Return both deployed contract instances
        return (dsc, engine, config);
    }
}
