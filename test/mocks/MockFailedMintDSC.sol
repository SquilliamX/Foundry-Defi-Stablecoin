// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFailedMintDSC
 * @notice A mock version of DecentralizedStableCoin that always fails to mint
 * @dev Used specifically for testing error handling in DSCEngine when minting fails
 */
contract MockFailedMintDSC is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    /*
    In future versions of OpenZeppelin contracts package, Ownable must be declared with an address of the contract owner
    as a parameter.
    For example:
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) {}
    Related code changes can be viewed in this commit:
    https://github.com/OpenZeppelin/openzeppelin-contracts/commit/13d5e0466a9855e9305119ed383e54fc913fdc60
    */

    /**
     * @notice Creates a new mock DSC token that fails minting
     * @dev Initializes with name "DecentralizedStableCoin" and symbol "DSC"
     */
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    /**
     * @notice Mock burn function that mimics the original DSC's burn functionality
     * @param _amount The amount of tokens to burn
     * @dev Only the owner can burn tokens
     */
    function burn(uint256 _amount) public override onlyOwner {
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
     * @notice Mock mint function that always returns false to simulate mint failure
     * @param _to The address to (not) mint tokens to
     * @param _amount The amount of tokens to (not) mint
     * @dev Used in DSCEngineTest.testRevertsIfMintFails()
     * @return false Always returns false to simulate mint failure
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        // Always return false to simulate mint failure
        return false;
    }
}
