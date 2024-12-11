// SPDX-License-Identifier: MIT

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

pragma solidity 0.8.19;

// First, create a mock contract that will always fail transfers
contract MockFailedTransferERC20 is ERC20Mock {
    // Constructor matches ERC20Mock's constructor
    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance)
        ERC20Mock(name, symbol, initialAccount, initialBalance)
    {}

    // Override the transferFrom function to always return false
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false; // This will always fail.
    }
}
