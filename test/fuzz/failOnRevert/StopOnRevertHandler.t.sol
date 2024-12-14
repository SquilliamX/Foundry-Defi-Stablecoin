// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions.

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

contract StopOnRevertHandler is Test {
    // declare new variables at the contract level so variables are in scope for all functions
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timeMintIsCalled;
    address[] public usersWithCollateralDeposited;

    MockV3Aggregator public ethUsdPriceFeed;

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

        // initialize the ethUsdPriceFeed variable as a Mock of a pricefeed of weth
        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
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
        // push the msg.sender that the fuzzer generates into our array to keep track of him
        // double push - In a stateful fuzz test, the same function can be called multiple times with different inputs. So if the fuzzer calls depositCollateral() twice for the same msg.sender, that address will be pushed to the usersWithCollateralDeposited array twice.
        usersWithCollateralDeposited.push(msg.sender);
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

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        // If no one has deposited collateral, we can't mint
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        // Pick a user who has deposited collateral
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // Get the user's current DSC minted and collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        // Calculate maximum DSC that can be minted:
        // - collateralValueInUsd / 2: Maximum allowed DSC is 50% of collateral value
        // - Subtract totalDscMinted: Account for DSC already minted
        // - Cast to int256 to handle negative cases
        int256 maxDscToMint = int256(collateralValueInUsd / 2) - int256(totalDscMinted);

        // If user has already minted more than 50% of their collateral value,
        // maxDscToMint will be negative, so return early
        if (maxDscToMint < 0) {
            return;
        }

        // Bound the random amount between 0 and the maximum allowed mint amount
        amount = bound(amount, 0, uint256(maxDscToMint));

        // If the bounded amount is 0, return early since we can't mint 0 DSC
        if (amount == 0) {
            return;
        }

        // Mint the DSC tokens
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();

        timeMintIsCalled++;
    }

    // This breaks our invariant test suite as if the price of the collateral plummets in a crash, our entire system would break. This is why we are using weth and wbtc as collateral and not memecoins. This is a known issue.
    // function updateCollateralPrice(uint96 newPrice) public {
    //     // save the random price inputted by the fuzzer as an int256. PriceFeeds take int256 and we chose a uint96 so that the number wouldn't be so big. We chose uint instead of int as the fuzz test parameter so the AI can be as random as possible.
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     // call the mock pricefeed's `updateAnswer` function to update the current price to the random `newPriceInt` inputted by the fuzzer.
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

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
