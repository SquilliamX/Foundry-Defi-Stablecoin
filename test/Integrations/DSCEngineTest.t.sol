// SPDX-License-Identifier: MIT

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSCEngine.s.sol";
import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferERC20} from "../Mocks/MockAlwaysFails.sol";

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
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);

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
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
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
}
