// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.sol";

/*
 * @title MockMoreDebtDSC (Mock DecentralizedStableCoin)
 * @author Squilliam
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
* 
 */
contract MockMoreDebtDSC is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    address mockAggregator;

    /*
    In future versions of OpenZeppelin contracts package, Ownable must be declared with an address of the contract owner
    as a parameter.
    For example:
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) {}
    Related code changes can be viewed in this commit:
    https://github.com/OpenZeppelin/openzeppelin-contracts/commit/13d5e0466a9855e9305119ed383e54fc913fdc60
    */

    /**
     * @notice Creates a new mock DSC token that manipulates price feed for testing
     * @param _mockAggregator The address of the price feed to manipulate
     * @dev Initializes with name "DecentralizedStableCoin" and symbol "DSC"
     */
    constructor(address _mockAggregator) ERC20("DecentralizedStableCoin", "DSC") {
        mockAggregator = _mockAggregator;
    }

    /**
     * @notice Mock burn function that crashes the price feed
     * @param _amount The amount of tokens to burn
     * @dev Sets price to 0 before burning to simulate a scenario where liquidation doesn't improve health factor
     */
    function burn(uint256 _amount) public override onlyOwner {
        // We crash the price
        MockV3Aggregator(mockAggregator).updateAnswer(0);
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /**
     * @notice Mock mint function that follows standard DSC minting rules
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     * @return bool Always returns true if mint succeeds
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
