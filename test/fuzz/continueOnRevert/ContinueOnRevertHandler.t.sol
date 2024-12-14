// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions.

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract ContinueOnRevertHandler is Test {
    // declare new variables at the contract level so variables are in scope for all functions
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    // why don't we do max uint256? because if we deposit the max uint256, then the next stateful fuzz test run is +1 or more, it will revert.
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        // define variables declared at contract level at set them when this contract is first deployed
        dsce = _dscEngine;
        dsc = _dsc;

        // Get the list of allowed collateral tokens from DSCEngine and save it in a new array named collateralTokens
        address[] memory collateralTokens = dsce.getCollateralTokens();

        // Cast the tokens to ERC20Mock type for testing. This ensures our fuzzing tests are always aligned with the actual system configuration, making the tests more reliable and maintainable while also being able to mint tokens for the pranked user
        // Cast the first collateral token address (index 0) to an ERC20Mock type and assign it to weth
        // This assumes the first token in the collateralTokens array is WETH
        weth = ERC20Mock(collateralTokens[0]);
        // Cast the second collateral token address (index 1) to an ERC20Mock type and assign it to wbtc
        // This assumes the second token in the collateralTokens array is WBTC
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    // in the handlers functions, what ever parameters you have are going to be randomized
    // function depositCollateral(address collateral, uint256 amountCollateral) public {
    // this does not work because it chooses a random collateral address and tries to deposit it, when our DSCEngine only takes weth and btc. Also it could try to deposit 0 amount, which will fail because our DSCEngine reverts on 0 transfers.
    // dsce.depositCollateral(collateral, amountCollateral);
    // }

    // to fix random collateral address, we are going to tell foundry to only deposit either weth or wbtc.
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Gets either WETH or WBTC token based on whether collateralSeed is even or odd and saves it as a variable named collateral
        // This ensures we only test with valid collateral tokens that our system accepts
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Bound the amountCollateral to be between:
        // - Minimum: 1 (since we can't deposit 0)
        // - Maximum: MAX_DEPOSIT_SIZE (type(uint96).max)
        // This prevents:
        // 1. Zero deposits which would revert
        // 2. Deposits so large they could overflow in subsequent tests
        // 3. Ensures amounts are realistic and within system limits
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); // The bound function is a Foundry utility (from forge-std) that constrains a fuzzed value to be within a specific range.

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);

        // Call the DSCEngine's depositCollateral function with:
        // 1. The selected collateral token's address
        // 2. The randomly generated amount of collateral to deposit
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Get either WETH or WBTC token based on the collateralSeed
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // Get the maximum amount of collateral this user has deposited in the DSCEngine
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));

        // Bound the random amountCollateral to be between 0 and the user's actual collateral balance
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        // However, if there was a bug in the code allowing users to redeem more than they deposit, the line above would not catch it. What would catch it is `fail_on_revert = false` and the following line:
        // amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        //`fail_on_revert = false` would catch this bug and `fail_on_revert = true` would not. keep this in mind. fuzzing is an art.

        // If the bounded amount is 0, return early since we can't redeem 0 collateral
        if (amountCollateral == 0) {
            return;
        }

        // Call DSCEngine's redeemCollateral function as the msg.sender
        // This will:
        // 1. Update internal accounting
        // 2. Transfer collateral back to user
        // 3. Check health factor remains valid
        vm.prank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount) public {
        // Bound the random amount to be between 1 and MAX_DEPOSIT_SIZE (type(uint96).max)
        // 1. We use 1 as minimum because DSCEngine doesn't allow minting 0 DSC
        // 2. We use MAX_DEPOSIT_SIZE to prevent overflow issues in subsequent tests
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        // Note: the mintDsc function in our DSCEngine requires the mint function to revert if the health factor is broken; but if we set the health factor to be greater than 1 here in this fuzz test, then we are making this too specific. We want to test all scenarios to see if there are bugs. This is an example of why you would want two fuzz tests, one of `fail_on_revert = true` and `fail_on_revert = false`.

        // Note: We intentionally don't check the health factor here
        // This allows us to test scenarios where:
        // 1. Users try to mint without sufficient collateral
        // 2. Users try to mint amounts that would break their health factor
        // 3. Edge cases in the minting process
        // Since this is a "continueOnRevert" test, we want to try these "invalid" operations

        // Call mintDsc as the msg.sender (pranked user)
        // This will:
        // 1. Update internal DSC minted accounting in DSCEngine
        // 2. Check health factor in DSCEngine
        // 3. Mint actual DSC tokens if health factor is good
        // 4. Revert if health factor would break (which is fine in this test)
        vm.prank(msg.sender);
        dsce.mintDsc(amount);
    }

    //////////////////////////
    //   Helper Functions   //
    /////////////////////////

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        // if the collateralSeed(number) inputted divided by 2 has a remainder of 0, then return the weth address.
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        // if the collateralSeed(number) inputted divided by 2 has a remainder of anything else(1), then return the wbtc address.
        return wbtc;
    }
}
