// SPDX-License-Identifier: MIT

// What are our Invariants?
//  - total supply of collateral should be more than the total value of borrowed tokens
//  - Getter view functions should never revert

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSCEngine.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {StopOnRevertHandler} from "./StopOnRevertHandler.t.sol";

contract FailOnRevertInvariants is StdInvariant, Test {
    // declare new variables at the contract level so variables are in scope for all functions
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    StopOnRevertHandler handler;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() external {
        // define variables declared at contract level through our deployment script variable
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        // deploys a new handler contract and saves it as a variable named handler.
        // Handler contract has a constructor that takes the `DSCEngine _dscEngine, DecentralizedStableCoin _dsc` so we pass them here
        handler = new StopOnRevertHandler(dsce, dsc);
        // calls `targetContract` from parent contract `StdInvariant` to tell foundry that it has access to all functions in our handler contract and to call them in a random order with random data.
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply_FailOnRevert() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt

        // gets the total supply of dsc in the entire world. We know that the only way to mint DSC is through the DSCEngine. DSC is the debt users mint.
        uint256 totalSupply = dsc.totalSupply();

        // gets the balance of all the weth tokens in the DSCEngine contract and saves it as a variable named totalWethDeposited.
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dsce));

        // gets the balance of all the wbtc tokens in the DSCEngine contract and saves it as a variable named totalBtcDeposited.
        uint256 totalBtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        // calls the getUsdValue function from our DSCEngine and passes it the weth token and the total amount deposited. This will get the value of all the weth in our DSCEngine contract in terms of USD
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);

        // calls the getUsdValue function from our DSCEngine and passes it the wbtc token and the total amount deposited. This will get the value of all the wbtc in our DSCEngine contract in terms of USD
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);

        // asserting that the value of all the collateral in the protocol is greater than all the debt.
        assert(wethValue + wbtcValue >= totalSupply);
    }

    // all smart contracts should have this to make sure that getter functions always work.
    function invariant_gettersCantRevert() public view {
        dsce.getAdditionalFeedPrecision();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getDsc();
        // dsce.getTokenAmountFromUsd();
        // dsce.getCollateralTokenPriceFeed();
        // dsce.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}
