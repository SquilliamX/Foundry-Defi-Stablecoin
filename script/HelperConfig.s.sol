// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// Import necessary contracts for mocking and scripting
import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/Mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    // Define a struct to hold all our network configuration data
    // This makes it easier to pass around network-specific addresses
    struct NetworkConfig {
        address wethUsdPriceFeed; // Price feed for ETH/USD
        address wbtcUsdPriceFeed; // Price feed for BTC/USD
        address weth; // WETH token address
        address wbtc; // WBTC token address
        uint256 deployerKey; // Private key for deployment
    }

    // Constants for mock price feed configuration
    uint8 public constant DECIMALS = 8; // Chainlink price feeds use 8 decimals
    int256 public constant ETH_USD_PRICE = 2000e8; // Mock ETH price of $2000
    int256 public constant BTC_USD_PRICE = 1000e8; // Mock BTC price of $1000
    uint256 public constant INITIAL_BALANCE = 1000e8; // Initial balance for mock tokens
    // Default private key for local testing (Anvil's first private key)
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Store the active network configuration
    NetworkConfig public activeNetworkConfig;

    // Constructor determines which network config to use based on chainId
    constructor() {
        if (block.chainid == 11155111) {
            // If we're on Sepolia testnet
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            // For any other network (local, mainnet, etc)
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    // Returns configuration for Sepolia testnet with real contract addresses
    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD price feed on Sepolia
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC / USD price feed on Sepolia
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // WETH token on Sepolia
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // WBTC token on Sepolia
            deployerKey: vm.envUint("PRIVATE_KEY") // Get deployer key from .env file for testing purposes
        });
    }

    // Returns or creates configuration for local testing with mock contracts
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If config already exists, return it
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // Start broadcasting transactions for mock deployment
        vm.startBroadcast();

        // Deploy mock price feeds and tokens
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, INITIAL_BALANCE);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, INITIAL_BALANCE);

        vm.stopBroadcast();

        // Return config with mock addresses
        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}