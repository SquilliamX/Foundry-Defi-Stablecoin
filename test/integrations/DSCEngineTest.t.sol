// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DeployDSC} from "script/DeployDSCEngine.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol"; Updated mock location
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransferDSC.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    // Core contract instances
    DSCEngine public dsce; // Main engine contract instance
    DecentralizedStableCoin public dsc; // Stablecoin contract instance
    HelperConfig public helperConfig; // Configuration helper contract instance

    // Price feed and token addresses from helper config
    address public ethUsdPriceFeed; // Chainlink ETH/USD price feed address
    address public btcUsdPriceFeed; // Chainlink BTC/USD price feed address
    address public weth; // Wrapped ETH token address
    address public wbtc; // Wrapped BTC token address
    uint256 public deployerKey; // Private key of the deployer

    // Test configuration values
    uint256 amountCollateral = 10 ether; // Standard collateral amount for tests (10 ETH)
    uint256 amountToMint = 100 ether; // Standard DSC amount to mint in tests (100 DSC)
    address public user = address(1); // Standard user address for testing

    // Constants for testing
    uint256 public constant STARTING_USER_BALANCE = 10 ether; // Initial balance given to test users
    uint256 public constant MIN_HEALTH_FACTOR = 1e18; // Minimum health factor before liquidation (1.0)
    uint256 public constant LIQUIDATION_THRESHOLD = 50; // Collateral threshold for liquidation (50%)

    // Liquidation test variables
    address public liquidator = makeAddr("liquidator"); // Address of the liquidator
    uint256 public collateralToCover = 20 ether; // Amount of collateral to cover in liquidation

    // Arrays for token setup
    address[] public tokenAddresses; // Array to store allowed collateral token addresses
    address[] public feedAddresses; // Array to store corresponding price feed addresses

    function setUp() external {
        // Create a new instance of the deployment script
        DeployDSC deployer = new DeployDSC();

        // Run the deployment script which:
        // 1. Deploys the DecentralizedStableCoin (DSC) contract
        // 2. Deploys the DSCEngine contract
        // 3. Returns configuration helper
        (dsc, dsce, helperConfig) = deployer.run();

        // Get the network configuration values from the helper:
        // - ETH/USD price feed address
        // - BTC/USD price feed address
        // - WETH token address
        // - WBTC token address
        // - Deployer's private key
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        // If we're on a local Anvil chain (chainId 31337)
        // Give our test user some ETH to work with
        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }

        // Mint initial balances of WETH and WBTC to our test user
        // This allows the user to have tokens to deposit as collateral
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    /**
     * @notice Tests that the constructor reverts when token and price feed arrays have different lengths
     * @dev This ensures proper initialization of collateral tokens and their price feeds
     * Test sequence:
     * 1. Push WETH to token array
     * 2. Push ETH/USD and BTC/USD to price feed array
     * 3. Attempt to deploy DSCEngine with mismatched arrays
     * 4. Verify it reverts with correct error
     */
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        // Setup: Create mismatched arrays
        tokenAddresses.push(weth); // Add only one token
        feedAddresses.push(ethUsdPriceFeed); // Add two price feeds
        feedAddresses.push(btcUsdPriceFeed); // Creating a length mismatch

        // Expect revert when arrays don't match in length
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    //////////////////
    // Price Tests //
    //////////////////

    /**
     * @notice Tests the conversion from USD value to token amount
     * @dev Verifies that getTokenAmountFromUsd correctly calculates token amounts based on price feeds
     * Test sequence:
     * 1. Request conversion of $100 worth of WETH
     * 2. With ETH price at $2000 (from mock), expect 0.05 WETH
     * 3. Compare actual result with expected amount
     */
    function testGetTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    /**
     * @notice Tests the conversion from token amount to USD value
     * @dev Verifies that getUsdValue correctly calculates USD value based on price feeds
     * Test sequence:
     * 1. Set test amount to 15 ETH
     * 2. With ETH price at $2000 (from mock), expect $30,000
     * 3. Compare actual result with expected value
     */
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30_000e18; // $30,000 in USD
        uint256 usdValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////

    // Tests that the contract reverts if transferFrom fails during collateral deposit
    function testRevertsIfTransferFromFails() public {
        // Setup - Get the owner's address (msg.sender in this context)
        address owner = msg.sender;

        // Create new mock token contract that will fail transfers, deployed by owner
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();

        // Setup array with mock token as only allowed collateral
        tokenAddresses = [address(mockDsc)];
        // Setup array with ETH price feed for the mock token
        feedAddresses = [ethUsdPriceFeed];

        // Deploy new DSCEngine instance with mock token configuration
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));

        // Mint some mock tokens to our test user
        mockDsc.mint(user, amountCollateral);

        // Transfer ownership of mock token to the DSCEngine
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        // Start impersonating our test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's tokens
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);

        // Expect the transaction to revert with TransferFailed error
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        // Attempt to deposit collateral (this should fail)
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);

        // Stop impersonating the user
        vm.stopPrank();
    }

    // Tests that the contract reverts if trying to deposit zero collateral
    function testRevertsIfCollateralZero() public {
        // Start impersonating our test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);

        // Expect revert with NeedsMoreThanZero error when attempting to deposit 0
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        // Attempt to deposit 0 collateral (this should fail)
        dsce.depositCollateral(weth, 0);

        // Stop impersonating the user
        vm.stopPrank();
    }

    // Tests that the contract reverts if trying to deposit an unapproved token
    function testRevertsWithUnapprovedCollateral() public {
        // Create a new random ERC20 token
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", user, 100e18);

        // Start impersonating our test user
        vm.startPrank(user);

        // Expect revert with TokenNotAllowed error when trying to deposit unapproved token
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randToken)));
        // Attempt to deposit unapproved token as collateral (this should fail)
        dsce.depositCollateral(address(randToken), amountCollateral);

        // Stop impersonating the user
        vm.stopPrank();
    }

    // Modifier used to setup a successful collateral deposit for other tests
    modifier depositedCollateral() {
        // Start impersonating our test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // Deposit the collateral
        dsce.depositCollateral(weth, amountCollateral);
        // Stop impersonating the user
        vm.stopPrank();
        _;
    }

    // Tests that user can deposit collateral without minting DSC
    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        // Check user's DSC balance
        uint256 userBalance = dsc.balanceOf(user);
        // Verify user has no DSC (only deposited collateral)
        assertEq(userBalance, 0);
    }

    // Tests that deposited collateral is properly recorded in account information
    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        // Get user's account information (DSC minted and collateral value)
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        // Calculate how much collateral should have been deposited based on USD value
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        // Verify no DSC was minted
        assertEq(totalDscMinted, 0);
        // Verify deposited collateral matches expected amount
        assertEq(expectedDepositedAmount, amountCollateral);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    // Modifier to set up the test state with collateral deposited and DSC minted
    modifier depositedCollateralAndMintedDsc() {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve the DSCEngine contract to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // Deposit collateral and mint DSC in one transaction
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Stop impersonating the user
        vm.stopPrank();
        _;
    }

    // Test to verify that minting works properly with deposited collateral
    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        // Get the user's DSC balance after minting
        uint256 userBalance = dsc.balanceOf(user);
        // Verify that the user's DSC balance matches the amount we tried to mint
        assertEq(userBalance, amountToMint);
    }

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
        // ARRANGE - Setup
        // Create a new mock DSC contract that will fail mint operations
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        // Set up allowed collateral tokens array with WETH
        tokenAddresses = [weth];
        // Set up corresponding price feed addresses
        feedAddresses = [ethUsdPriceFeed];
        // Get the owner's address
        address owner = msg.sender;
        // Deploy new DSCEngine with mock DSC
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        // Transfer ownership of mock DSC to the engine
        mockDsc.transferOwnership(address(mockDsce));

        // ARRANGE - User setup
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve the mock DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);

        // ACT & ASSERT
        // Expect the transaction to revert with MintFailed error
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        // Attempt to deposit collateral and mint DSC (should fail)
        mockDsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Stop impersonating the user
        vm.stopPrank();
    }

    // Test to verify that minting fails when attempting to mint zero DSC
    function testRevertsIfMintAmountIsZero() public {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // First deposit collateral and mint some DSC successfully
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Expect revert when trying to mint zero DSC
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        // Attempt to mint zero DSC (should fail)
        dsce.mintDsc(0);
        // Stop impersonating the user
        vm.stopPrank();
    }

    // Test to verify that DSC can be minted after depositing collateral
    function testCanMintDsc() public depositedCollateral {
        // Impersonate the test user
        vm.prank(user);
        // Attempt to mint DSC
        dsce.mintDsc(amountToMint);

        // Get the user's DSC balance
        uint256 userBalance = dsc.balanceOf(user);
        // Verify that the user's DSC balance matches the amount we tried to mint
        assertEq(userBalance, amountToMint);
    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    // Tests that burning DSC fails when attempting to burn zero tokens
    function testRevertsIfBurnAmountIsZero() public {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // First deposit collateral and mint some DSC
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Expect the transaction to revert with NeedsMoreThanZero error
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        // Attempt to burn zero DSC (this should fail)
        dsce.burnDsc(0);
        // Stop impersonating the user
        vm.stopPrank();
    }

    // Tests that a user cannot burn more DSC than they own
    function testCantBurnMoreThanUserHas() public {
        // Start impersonating the test user
        vm.prank(user);
        // Expect the transaction to revert (user has no DSC to burn)
        vm.expectRevert();
        // Attempt to burn 1 DSC when user has none (this should fail)
        dsce.burnDsc(1);
    }

    // Tests that a user can successfully burn their DSC
    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's DSC tokens
        dsc.approve(address(dsce), amountToMint);
        // Burn all of user's DSC tokens
        dsce.burnDsc(amountToMint);
        // Stop impersonating the user
        vm.stopPrank();

        // Get user's final DSC balance
        uint256 userBalance = dsc.balanceOf(user);
        // Verify that user's DSC balance is now zero
        assertEq(userBalance, 0);
    }

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    // Tests that redeeming collateral fails if the transfer operation fails
    function testRevertsIfTransferFails() public {
        // Arrange - Setup
        // Get the owner's address for deployment
        address owner = msg.sender;
        // Deploy a mock token that will fail transfers
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        // Setup token addresses array with only the mock token
        tokenAddresses = [address(mockDsc)];
        // Setup price feed addresses array with ETH/USD feed
        feedAddresses = [ethUsdPriceFeed];
        // Deploy new DSCEngine with mock token configuration
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        // Mint mock tokens to test user
        mockDsc.mint(user, amountCollateral);

        // Transfer ownership of mock token to DSCEngine
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User Setup
        vm.startPrank(user);
        // Approve DSCEngine to spend user's tokens
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);
        // Deposit collateral into the system
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);

        // Act & Assert
        // Expect the transaction to revert with TransferFailed error
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        // Attempt to redeem collateral (should fail due to mock transfer failure)
        mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

    // Tests that redeeming fails when attempting to redeem zero collateral
    function testRevertsIfRedeemAmountIsZero() public {
        // Start impersonating test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // First deposit collateral and mint DSC
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Expect revert when trying to redeem zero collateral
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        // Attempt to redeem zero collateral (should fail)
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    // Tests that collateral can be successfully redeemed
    function testCanRedeemCollateral() public depositedCollateral {
        // Start impersonating test user
        vm.startPrank(user);
        // Redeem all deposited collateral
        dsce.redeemCollateral(weth, amountCollateral);
        // Get user's final WETH balance
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        // Verify user received back their full collateral amount
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    // Tests that attempting to redeem zero collateral for DSC fails
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's DSC tokens
        dsc.approve(address(dsce), amountToMint);
        // Expect the transaction to revert with NeedsMoreThanZero error
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        // Attempt to redeem zero collateral for DSC (should fail)
        dsce.redeemCollateralForDsc(weth, 0, amountToMint);
        // Stop impersonating the user
        vm.stopPrank();
    }

    // Tests that collateral can be successfully redeemed for DSC
    function testCanRedeemDepositedCollateral() public {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // First deposit collateral and mint DSC
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Approve DSCEngine to spend user's DSC
        dsc.approve(address(dsce), amountToMint);
        // Redeem all collateral for DSC
        dsce.redeemCollateralForDsc(weth, amountCollateral, amountToMint);
        // Stop impersonating the user
        vm.stopPrank();

        // Get user's final DSC balance
        uint256 userBalance = dsc.balanceOf(user);
        // Verify that user's DSC balance is now zero
        assertEq(userBalance, 0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    // Tests that the health factor is calculated correctly for a user's position
    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dsce.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collateral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor

        // Verify that the calculated health factor matches expected value
        assertEq(healthFactor, expectedHealthFactor);
    }

    // Tests that the health factor can go below 1 when collateral value drops
    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        // Set new ETH price to $18 (significant drop from original price)
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        // we need $200 at all times if we have $100 of debt
        // Update the ETH/USD price feed with new lower price
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Get user's new health factor after price drop
        uint256 userHealthFactor = dsce.getHealthFactor(user);

        // Health factor calculation explanation:
        // 180 (ETH price) * 50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION)
        // / 100 (PRECISION) = 90 / 100 (totalDscMinted) = 0.9

        // Verify health factor is now below 1 (0.9)
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // Testing that liquidation must improve the health factor of the user being liquidated
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        // Create a mock DSC contract that will create more debt than expected
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);

        // Set up arrays with allowed collateral token (WETH) and its price feed
        tokenAddresses = [weth];
        feedAddresses = [ethUsdPriceFeed];

        // Get the deployer's address
        address owner = msg.sender;

        // Deploy new DSCEngine instance with mock DSC configuration
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));

        // Transfer ownership of mock DSC to the DSCEngine
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        // Start acting as the user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(mockDsce), amountCollateral);
        // Deposit collateral and mint DSC
        mockDsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        // Set up liquidator with collateral
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        // Start acting as the liquidator
        vm.startPrank(liquidator);
        // Approve DSCEngine to spend liquidator's WETH
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        // Amount of debt the liquidator will try to cover
        uint256 debtToCover = 10 ether;
        // Deposit collateral and mint DSC for liquidator
        mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        // Approve DSC spending
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        // Update ETH price to $18 to make the position undercollateralized
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        // Expect the liquidation to revert because it doesn't improve health factor
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        // Attempt to liquidate the user
        mockDsce.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    }

    // Tests that you cannot liquidate a user with a healthy position
    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        // Mint collateral for the liquidator
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        // Start acting as the liquidator
        vm.startPrank(liquidator);
        // Approve DSCEngine to spend liquidator's WETH
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        // Deposit collateral and mint DSC for liquidator
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        // Approve DSC spending
        dsc.approve(address(dsce), amountToMint);

        // Expect the liquidation to revert because user's health factor is good
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        // Attempt to liquidate a healthy position
        dsce.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    // Modifier to set up a common liquidation scenario for multiple test cases
    modifier liquidated() {
        // SETUP USER'S POSITION
        // Start impersonating the user for subsequent transactions
        vm.startPrank(user);
        // Approve DSCEngine contract to spend user's WETH tokens
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // User deposits collateral and mints DSC in one transaction
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        // Stop impersonating the user
        vm.stopPrank();

        // MANIPULATE PRICE TO TRIGGER LIQUIDATION
        // Set new ETH price to $18 (down from original price) to make position undercollateralized
        int256 ethUsdUpdatedPrice = 18e8; // 18 USD with 8 decimal places
        // Update the price feed with new lower price
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Get user's health factor after price drop (for debugging/verification)
        uint256 userHealthFactor = dsce.getHealthFactor(user);

        // SETUP LIQUIDATOR'S POSITION
        // Mint WETH tokens to the liquidator's address
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        // PERFORM LIQUIDATION
        // Start impersonating the liquidator
        vm.startPrank(liquidator);
        // Approve DSCEngine to spend liquidator's WETH
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        // Liquidator deposits collateral and mints DSC to have funds for liquidation
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        // Approve DSCEngine to spend liquidator's DSC
        dsc.approve(address(dsce), amountToMint);
        // Execute the liquidation - covering the user's entire debt
        dsce.liquidate(weth, user, amountToMint);
        // Stop impersonating the liquidator
        vm.stopPrank();

        // Continue with the test function
        _;
    }

    // Tests that liquidator receives the correct amount of collateral
    function testLiquidationPayoutIsCorrect() public liquidated {
        // Get liquidator's final WETH balance
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);

        // Calculate expected WETH payout including the liquidation bonus
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

        // Hardcoded expected value for verification
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;

        // Verify liquidator received correct amount
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    // Tests that the user being liquidated still has remaining collateral
    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Calculate how much WETH was taken from the user
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

        // Convert liquidated amount to USD value
        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);

        // Calculate expected remaining collateral value
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth, amountCollateral) - (usdAmountLiquidated);

        // Get actual remaining collateral value
        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);

        // Hardcoded expected value for verification
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;

        // Verify remaining collateral values
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    // Tests that the liquidator takes on the user's debt
    function testLiquidatorTakesOnUsersDebt() public liquidated {
        // Get liquidator's DSC debt after liquidation
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);

        // Verify liquidator now owns the debt that was previously user's
        assertEq(liquidatorDscMinted, amountToMint);
    }

    // Tests that the liquidated user no longer has any debt
    function testUserHasNoMoreDebt() public liquidated {
        // Get user's remaining DSC debt after liquidation
        (uint256 userDscMinted,) = dsce.getAccountInformation(user);

        // Verify user's debt is now zero
        assertEq(userDscMinted, 0);
    }

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    // Tests that the price feed address is correctly mapped to the collateral token
    function testGetCollateralTokenPriceFeed() public {
        // Get the price feed address for WETH token
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        // Verify it matches the expected ETH/USD price feed address
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    // Tests that the array of collateral tokens contains the expected tokens
    function testGetCollateralTokens() public {
        // Get the array of allowed collateral tokens
        address[] memory collateralTokens = dsce.getCollateralTokens();
        // Verify WETH is at index 0 (first and only token in this test)
        assertEq(collateralTokens[0], weth);
    }

    // Tests that the minimum health factor constant is set correctly
    function testGetMinHealthFactor() public {
        // Get the minimum health factor from the contract
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        // Verify it matches the expected constant value (1e18)
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    // Tests that the liquidation threshold constant is set correctly
    function testGetLiquidationThreshold() public {
        // Get the liquidation threshold from the contract
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        // Verify it matches the expected constant value (50)
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    // Tests that the account information returns correct collateral value
    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        // Get account information and extract collateral value using destructuring
        (, uint256 collateralValue) = dsce.getAccountInformation(user);
        // Calculate expected collateral value in USD
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, amountCollateral);
        // Verify the returned value matches expected value
        assertEq(collateralValue, expectedCollateralValue);
    }

    // Tests that the collateral balance is correctly tracked for users
    function testGetCollateralBalanceOfUser() public {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // Deposit collateral
        dsce.depositCollateral(weth, amountCollateral);
        // Stop impersonating the user
        vm.stopPrank();
        // Get user's collateral balance
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(user, weth);
        // Verify balance matches deposited amount
        assertEq(collateralBalance, amountCollateral);
    }

    // Tests that the total account collateral value is calculated correctly
    function testGetAccountCollateralValue() public {
        // Start impersonating the test user
        vm.startPrank(user);
        // Approve DSCEngine to spend user's WETH
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        // Deposit collateral
        dsce.depositCollateral(weth, amountCollateral);
        // Stop impersonating the user
        vm.stopPrank();
        // Get total collateral value in USD
        uint256 collateralValue = dsce.getAccountCollateralValue(user);
        // Calculate expected USD value
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, amountCollateral);
        // Verify values match
        assertEq(collateralValue, expectedCollateralValue);
    }

    // Tests that the DSC token address is correctly stored
    function testGetDsc() public {
        // Get the DSC token address from the engine
        address dscAddress = dsce.getDsc();
        // Verify it matches our deployed DSC contract address
        assertEq(dscAddress, address(dsc));
    }

    // Tests that the liquidation precision constant is set correctly
    function testLiquidationPrecision() public {
        // Define expected liquidation precision value
        uint256 expectedLiquidationPrecision = 100;
        // Get actual liquidation precision from contract
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        // Verify values match
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
