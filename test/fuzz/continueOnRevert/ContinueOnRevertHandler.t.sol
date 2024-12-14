// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions.

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

/* 
* @dev: When running these tests, make sure to have `fail_on_revert = false` in your foundry.toml
*/
contract ContinueOnRevertHandler is Test {
    // using EnumerableSet for EnumerableSet.AddressSet;
    // using Randomish for EnumerableSet.AddressSet;

    // Deployed contracts to interact with
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        // Store the reference to the main DSCEngine contract that we'll be testing
        dscEngine = _dscEngine;
        // Store the reference to the DecentralizedStableCoin contract that we'll be testing
        dsc = _dsc;

        // Get the array of allowed collateral token addresses from DSCEngine
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        // Store the first collateral token (WETH) from the array for easy access
        weth = ERC20Mock(collateralTokens[0]);
        // Store the second collateral token (WBTC) from the array for easy access
        wbtc = ERC20Mock(collateralTokens[1]);

        // Get and store the Chainlink price feed address for WETH from DSCEngine
        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        // Get and store the Chainlink price feed address for WBTC from DSCEngine
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    // FUNCTIONS TO INTERACT WITH

    ///////////////
    // DSCEngine //
    ///////////////
    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Bound the collateral amount between 0 and MAX_DEPOSIT_SIZE to prevent overflow
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        // Get either WETH or WBTC based on the collateralSeed
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Mint the collateral tokens to the caller (this simulates having the tokens)
        collateral.mint(msg.sender, amountCollateral);
        // Deposit the collateral into the DSCEngine contract
        dscEngine.depositCollateral(address(collateral), amountCollateral);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Bound the redemption amount between 0 and MAX_DEPOSIT_SIZE to prevent overflow
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        // Get either WETH or WBTC based on the collateralSeed
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Attempt to redeem collateral from the DSCEngine contract
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function burnDsc(uint256 amountDsc) public {
        // Bound the burn amount to the caller's current DSC balance
        // This prevents trying to burn more than the user has
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        // Attempt to burn the specified amount of DSC tokens
        dscEngine.burnDsc(amountDsc);
    }

    function mintDsc(uint256 amountDsc) public {
        // Bound the mint amount between 0 and MAX_DEPOSIT_SIZE to prevent overflow
        amountDsc = bound(amountDsc, 0, MAX_DEPOSIT_SIZE);
        // Mint the specified amount of DSC tokens to the caller
        dsc.mint(msg.sender, amountDsc);
    }

    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        // Get either WETH or WBTC based on the collateralSeed
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Attempt to liquidate the specified user's position in the DSCEngine
        dscEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /////////////////////////////
    // DecentralizedStableCoin //
    /////////////////////////////
    function transferDsc(uint256 amountDsc, address to) public {
        // Bound the transfer amount to the sender's current DSC balance
        // This prevents trying to transfer more tokens than the user has
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));

        // Use vm.prank to set msg.sender as the caller for the next function call
        // This is a Foundry cheatcode that allows us to simulate calls from different addresses
        vm.prank(msg.sender);

        // Call the transfer function on the DSC contract to send tokens
        // Parameters:
        // - to: destination address for the tokens
        // - amountDsc: amount of DSC tokens to transfer
        dsc.transfer(to, amountDsc);
    }

    /////////////////////////////
    // Aggregator //
    /////////////////////////////
    function updateCollateralPrice(uint128, /* newPrice */ uint256 collateralSeed) public {
        // We're not using the newPrice parameter (it's commented out)
        // Instead, we're setting price to 0 to test extreme price scenarios
        int256 intNewPrice = 0;

        // Get either WETH or WBTC based on the collateralSeed using our helper function
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Get the price feed associated with the selected collateral token
        MockV3Aggregator priceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(collateral)));

        // Update the price feed with our new price (0 in this case)
        // This simulates a price crash scenario for testing
        priceFeed.updateAnswer(intNewPrice);
    }

    /// Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        // If the seed is even, return WETH
        // If the seed is odd, return WBTC
        // This provides a deterministic but pseudo-random way to select collateral
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function callSummary() external view {
        // Log the total amount of WETH held by the DSCEngine contract
        console.log("Weth total deposited", weth.balanceOf(address(dscEngine)));
        // Log the total amount of WBTC held by the DSCEngine contract
        console.log("Wbtc total deposited", wbtc.balanceOf(address(dscEngine)));
        // Log the total supply of DSC tokens in circulation
        console.log("Total supply of DSC", dsc.totalSupply());
    }
}
