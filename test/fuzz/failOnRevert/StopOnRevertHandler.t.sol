// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions.

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract StopOnRevertHandler is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

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
        // Store the first collateral token (WETH) from the array
        weth = ERC20Mock(collateralTokens[0]);
        // Store the second collateral token (WBTC) from the array
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
        // Ensure amount is at least 1 and no larger than MAX_DEPOSIT_SIZE (uint96.max)
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        // Get either WETH or WBTC based on whether collateralSeed is even or odd
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Start a new transaction context for msg.sender
        vm.startPrank(msg.sender);
        // Mint the collateral tokens to the user (simulating they have the tokens)
        collateral.mint(msg.sender, amountCollateral);
        // Approve DSCEngine to spend the user's collateral tokens
        collateral.approve(address(dscEngine), amountCollateral);
        // Deposit the collateral into DSCEngine
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        // End the transaction context
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Get either WETH or WBTC based on whether collateralSeed is even or odd
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Get the maximum amount of collateral the user has deposited
        uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        // Ensure amount is between 0 and user's max collateral
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        // If amount is 0, return early to avoid unnecessary transactions
        if (amountCollateral == 0) {
            return;
        }
        // Execute redemption as msg.sender
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function burnDsc(uint256 amountDsc) public {
        // Ensure amount is between 0 and user's DSC balance
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        // If amount is 0, return early to avoid unnecessary transactions
        if (amountDsc == 0) {
            return;
        }
        // Start a new transaction context for msg.sender
        vm.startPrank(msg.sender);
        // Approve DSCEngine to spend the user's DSC tokens
        dsc.approve(address(dscEngine), amountDsc);
        // Burn the DSC tokens
        dscEngine.burnDsc(amountDsc);
        // End the transaction context
        vm.stopPrank();
    }

    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        // Get system's minimum required health factor
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        // Get user's current health factor
        uint256 userHealthFactor = dscEngine.getHealthFactor(userToBeLiquidated);
        // If user's health factor is above minimum, they can't be liquidated so return early
        if (userHealthFactor >= minHealthFactor) {
            return;
        }
        // Ensure debt amount is between 1 and uint96.max
        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
        // Get either WETH or WBTC based on whether collateralSeed is even or odd
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Execute the liquidation
        dscEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /////////////////////////////
    // DecentralizedStableCoin //
    /////////////////////////////
    function transferDsc(uint256 amountDsc, address to) public {
        // If the destination address is zero address (0x0), set it to address(1)
        // This prevents transfers to the zero address which would revert our fuzz
        if (to == address(0)) {
            to = address(1);
        }

        // Bound the transfer amount between 0 and the sender's current DSC balance
        // This ensures we don't try to transfer more than the user has
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));

        // Start a transaction context as msg.sender using Forge's vm.prank
        vm.prank(msg.sender);

        // Execute the transfer of DSC tokens from msg.sender to the destination address
        // This calls the transfer function on the DecentralizedStableCoin contract
        dsc.transfer(to, amountDsc);
    }

    /////////////////////////////
    // Aggregator //
    /////////////////////////////
    // This breaks our invariant test suite as if the price of the collateral plummets in a crash, our entire system would break. This is why we are using weth and wbtc as collateral and not memecoins. This is a known issue.
    // function updateCollateralPrice(uint96 newPrice) public {
    //     // save the random price inputted by the fuzzer as an int256. PriceFeeds take int256 and we chose a uint96 so that the number wouldn't be so big. We chose uint instead of int as the fuzz test parameter so the fuzzer can be as random as possible.
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     // call the mock pricefeed's `updateAnswer` function to update the current price to the random `newPriceInt` inputted by the fuzzer.
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

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
}
