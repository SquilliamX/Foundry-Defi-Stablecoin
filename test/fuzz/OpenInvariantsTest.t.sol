// SPDX-License-Identifier: MIT

// Have our invariants/properties of the system that should always hold.

// the first question to always want to ask when writing a fuzz test is:
// What are our Invariants?
//  - total supply of collateral should be more than the total value of borrowed tokens
//  - Getter view functions should never revert

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    // declare new variables at the contract level so variables are in scope for all functions
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        // define variables declared at contract level through our deployment script variable
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();

        (,, weth, wbtc,) = config.activeNetworkConfig();

        // calls `targetContract` from parent contract `StdInvariant` to tell foundry that it has access to all functions in our DSCEngine contract and to call them in a random order with random data.
        targetContract(address(dsce));
    }

    function invariant_openProtocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt

        // gets the total supply of dsc in the entire world. We know that the only way to mint DSC is through the DSCEngine. DSC is the debt users mint.
        uint256 totalSupply = dsc.totalSupply();

        // gets the balance of all the weth tokens in the DSCEngine contract and saves it as a variable named totalWethDeposited.
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));

        // gets the balance of all the wbtc tokens in the DSCEngine contract and saves it as a variable named totalBtcDeposited.
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        // calls the getUsdValue function from our DSCEngine and passes it the weth token and the total amount deposited. This will get the value of all the weth in our DSCEngine contract in terms of USD
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);

        // calls the getUsdValue function from our DSCEngine and passes it the wbtc token and the total amount deposited. This will get the value of all the wbtc in our DSCEngine contract in terms of USD
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);

        // asserting that the value of all the collateral in the protocol is greater than all the debt.
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
