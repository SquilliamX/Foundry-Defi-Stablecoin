// SPDX-License-Identifier: MIT

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSCEngine.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferERC20} from "../mocks/MockFailedTransferERC20.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransferDSC.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

pragma solidity 0.8.19;

contract DSCEngineTest is Test {
    // declare needed variables at the contract level so our test functions can have access to them
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("USER");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    uint256 public constant AMOUNT_MINTED = 100e18;

    function setUp() public {
        // initialize the variables in setup function
        deployer = new DeployDSC();
        // get the values returns from the deployment script's `run` function and save the values to our variables dsc and dsce
        (dsc, dsce, config) = deployer.run();
        // get the values from the activeNetworkConfig from out Helperconfig script
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        // Give USER some WETH tokens before running tests
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////
    //     Constructor Tests    //
    /////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        // Push a single token (WETH) to the tokenAddresses array
        // This creates an array with length 1
        tokenAddresses.push(weth);

        // Push two price feeds (ETH/USD and BTC/USD) to the priceFeedAddresses array
        // This creates an array with length 2
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        // Expect the next contract deployment to revert with a specific error
        // This error is defined in DSCEngine.sol and is thrown when token and price feed arrays don't match
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);

        // Attempt to deploy a new DSCEngine with mismatched array lengths
        // This should fail because we have 1 token but 2 price feeds
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////
    //     Price Tests    //
    ///////////////////////
    function testGetUsdPriceValue() public {
        // 15 eth tokens(each eth token has 18 decimals)
        uint256 ethAmount = 15e18;
        // our helperconfig puts the eth price on anvil at 2,000/eth
        // 15e18 * 2000eth = 30,000e18
        uint256 expectedUsd = 30000e18;
        // calls getUsdValue, but getUsdValue needs two paramters, the token and the amount
        // so we pass the weth token we defined earlier from our helperconfig and we define the ethAmount earlier in this function
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        // Assert the the expectedUsd and the actualUsd are the same
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        // Define the USD amount we want to convert to WETH
        uint256 usdAmount = 100e18; // $100

        // Calculate the expected amount of WETH for the given USD amount
        // Based on the mock price of $2000 per ETH, $100 should convert to 0.05 ETH
        uint256 expectedWeth = 0.05 ether; // 5e16

        // Call the getTokenAmountFromUsd function to get the actual WETH amount
        // Pass the WETH token address and the USD amount
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);

        // Assert that the expected and actual WETH amounts are equal
        // This verifies that the conversion logic in getTokenAmountFromUsd is correct
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////////////
    //     depositCollateral Tests    //
    ///////////////////////////////////

    function testRevertsIfCollateralIs0() public {
        // Start acting as the USER
        vm.startPrank(USER);

        // USER approves DSCEngine (dsce) to spend 0 WETH tokens
        ERC20Mock(weth).approve(address(dsce), 0);

        // Expect the next call to revert with this specific error
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        // Try to deposit 0 collateral
        dsce.depositCollateral(weth, 0);

        // Stop acting as the USER
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        // deploy new mock token for testing
        ERC20Mock fakeTokenToTestWith = new ERC20Mock("fakeTokenToTestWith", "FTTTW", USER, AMOUNT_COLLATERAL);

        // all calls will come from the USER account
        vm.startPrank(USER);

        // we expect the next transaction to revert.
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);

        // we call the `depositCollateral` function with the new mock token we made and pass an amount(these are the parameters that the depositCollateral function takes)
        dsce.depositCollateral(address(fakeTokenToTestWith), AMOUNT_COLLATERAL);

        // stop simulating the USER's account
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        // Get the user's DSC minted amount and collateral value after depositing
        // totalDscMinted should be 0 since we haven't minted any DSC
        // collateralValueInUsd should be the USD value of our deposited WETH
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        // We expect totalDscMinted to be 0 since we only deposited collateral and didn't mint any DSC
        uint256 expectedTotalDscMinted = 0;

        // Convert the USD value back to WETH amount to compare with our deposit
        // This works because:
        // 1. We deposited AMOUNT_COLLATERAL (10 ether) of WETH
        // 2. getTokenAmountFromUsd converts collateralValueInUsd back to WETH amount
        // 3. These amounts should match if our deposit worked correctly
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        // Verify no DSC was minted
        assertEq(totalDscMinted, expectedTotalDscMinted);
        // Verify the deposited collateral amount matches what we expect
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testdepositCollateralrevertsWithTransferFailedWhenTransferFails() public {
        // Deploy our failing mock token
        MockFailedTransferERC20 mockToken =
            new MockFailedTransferERC20("FailingMockToken", "FMT", USER, AMOUNT_COLLATERAL);

        // Setup the token addresses and price feed addresses arrays
        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = address(mockToken);
        priceFeeds[0] = ethUsdPriceFeed; // Use the existing price feed

        // Deploy new DSCEngine with our mock token
        DSCEngine mockDsce = new DSCEngine(tokens, priceFeeds, address(dsc));

        // Approve tokens
        vm.startPrank(USER);
        mockToken.approve(address(mockDsce), AMOUNT_COLLATERAL);

        // Expect the depositCollateral call to revert with TransferFailed error
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////////////////
    //     modifier Tests     //
    ///////////////////////////

    function testMoreThanZeroModifier() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), 0);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    ////////////////////////////////////
    //     redeemCollateral Tests     //
    ///////////////////////////////////

    // this test found a bug of when users have no DSC minted, there health factor is not perfect when it should be.
    // function testUsersCollateralBalanceDecreasesWhenRedeemed() public depositedCollateral {
    //     uint256 startingUserBalance = dsce.getAccountCollateralValue(USER);
    //     vm.startPrank(USER);
    //     dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
    //     uint256 expectedUserbalance = 0;
    //     uint256 endingUserBalance = dsce.getAccountCollateralValue(USER);
    //     assertEq(expectedUserbalance, endingUserBalance);
    // }

    ////////////////////////////////
    //     HealthFactor Tests     //
    ///////////////////////////////

    function testRevertMintIfHealthFactorIsBroken() public depositedCollateral {
        uint256 amountDscToMint = 12000e18;
        vm.prank(USER);
        vm.expectRevert();
        dsce.mintDsc(amountDscToMint);
    }

    ////////////////////////////
    //     mintDsc Tests     //
    ///////////////////////////

    function testMintDsc() public depositedCollateral {
        uint256 mintedAmount = 1 ether;

        vm.prank(USER);
        dsce.mintDsc(mintedAmount);

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);

        assertEq(mintedAmount, totalDscMinted);
    }

    function testMintDscFailsIfMintFails() public {
        // Deploy our failing mock DSC
        MockFailedMintDSC mockFailedMintDsc = new MockFailedMintDSC();

        // Setup new DSCEngine with mock DSC
        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = weth;
        priceFeeds[0] = ethUsdPriceFeed;
        DSCEngine mockDsce = new DSCEngine(tokens, priceFeeds, address(mockFailedMintDsc));

        // Setup collateral for USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Try to mint DSC, expect it to fail
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.mintDsc(1 ether);
        vm.stopPrank();
    }

    ////////////////////////////
    //     burnDsc Tests     //
    ///////////////////////////

    function testDscMintedDecreasesAfterBurning() public depositedCollateral {
        // Setup: Mint some DSC first
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_MINTED);

        // Get starting DSC minted balance
        (uint256 startingDscMinted,) = dsce.getAccountInformation(USER);

        // Burn half of the minted DSC
        uint256 amountToBurn = AMOUNT_MINTED / 2;
        dsc.approve(address(dsce), amountToBurn);
        dsce.burnDsc(amountToBurn);

        // Get ending DSC minted balance
        (uint256 endingDscMinted,) = dsce.getAccountInformation(USER);

        // Assert that the DSC minted balance decreased by the correct amount
        assertEq(endingDscMinted, startingDscMinted - amountToBurn);
        vm.stopPrank();
    }

    function testTransferFromWorksWhenBurningDsc() public depositedCollateral {
        // Setup: Mint some DSC first
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_MINTED);

        // Get starting DSC balance of user
        uint256 userStartingDscBalance = dsc.balanceOf(USER);

        // Now approve and burn
        dsc.approve(address(dsce), AMOUNT_MINTED);
        dsce.burnDsc(AMOUNT_MINTED);

        // Get ending DSC balance of user
        uint256 userEndingDscBalance = dsc.balanceOf(USER);
        (uint256 dscMinted,) = dsce.getAccountInformation(USER);

        // Assert that:
        // 1. User's balance decreased by burn amount
        assertEq(userEndingDscBalance, userStartingDscBalance - AMOUNT_MINTED);
        // 2. User's DSC minted amount in DSCEngine is now 0
        assertEq(dscMinted, 0);
        vm.stopPrank();
    }

    function testRevertsWithCustomErrorWhenTransferFails() public {
        // Deploy our failing mock DSC
        MockFailedTransfer mockDsc = new MockFailedTransfer();

        // Setup new DSCEngine with mock DSC
        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = weth;
        priceFeeds[0] = ethUsdPriceFeed;
        DSCEngine mockDsce = new DSCEngine(tokens, priceFeeds, address(mockDsc));

        // Transfer ownership of mockDsc to mockDsce
        mockDsc.transferOwnership(address(mockDsce));

        // Setup collateral for USER and mint DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        mockDsce.mintDsc(1 ether); // Mint some DSC first

        // Try to burn DSC, expect it to fail
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.burnDsc(1 ether);
        vm.stopPrank();
    }

    /////////////////////////////
    //     liquidate Tests     //
    ////////////////////////////

    function testLiquidateRevertsWhenDebtToCoverIs0() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_MINTED);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
    }

    function testLiquidationRevertsIfHealthFactorIsGreaterThan1() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_MINTED); // 100e18
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_MINTED);
        vm.stopPrank();
    }

    function testTokenAmountFromDebtCovered() public depositedCollateral {
        // Setup: Create a user with an unhealthy position
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_MINTED); // mint 100 DSC
        vm.stopPrank();

        // Simulate price drop to make USER liquidatable
        // Current price is $2000, dropping to $1000 makes position unhealthy
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);

        // Calculate expected token amount
        // If covering 100 DSC and ETH price is $1000:
        // tokenAmountFromDebtCovered = 100 / 1000 = 0.1 ETH
        uint256 debtToCover = 100e18; // 100 DSC
        uint256 expectedTokenAmount = 0.1 ether; // 0.1 ETH

        // Get the actual token amount by calling getTokenAmountFromUsd directly
        uint256 actualTokenAmount = dsce.getTokenAmountFromUsd(weth, debtToCover);

        assertEq(actualTokenAmount, expectedTokenAmount);
    }
}
