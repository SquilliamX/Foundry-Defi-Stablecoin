// SPDX-License-Identifier: MIT

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSCEngine.s.sol";
import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

pragma solidity 0.8.19;

contract DSCEngineTest is Test {
    // declare needed variables at the contract level so our test functions can have access to them
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
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
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
    }

    //     Price Tests    //

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
}
