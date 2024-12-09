// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* 
 * @title DecentralizedStableCoin
 *@author Squilliam
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * 
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system
 * 
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    // ERC20Burnable inherits from the ERC20 contract so we need to use the ERC20 constructor and pass the arguments needed in the ERC20 constructor
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        // balance variable is the msg.sender's current balance
        uint256 balance = balanceOf(msg.sender);
        // if the amount they input is less than or equal to 0 revert.
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        // if the msg.sender's balance is less than the amount they try to burn, revert.
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        // calls the burn function from the parent class
        // `super` means to call the parent contract(ERC20Burnable) and call the function `burn` from the parent contract
        // super is used because we overrided the contract, and we also want to complete the if statements above and do the regular burn function in the parent contract
        super.burn(_amount);
    }

    // returns a boolean because we need to know if the mint works
    // will return true if the mint is successful
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        // if msg.sender inputs the 0 address, revert
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        // if msg.sender inputs a value of 0 to mint, revert
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        // if everything passes the if statements above, then mint the tokens to the address and amount inputted
        _mint(_to, _amount);
        // return true if mint is successful
        return true;
    }
}
