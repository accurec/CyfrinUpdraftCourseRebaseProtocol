// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract Vault {
    event Vault__Deposit(address indexed sender, uint256 amount);
    event Vault__Redeemed(address indexed sender, uint256 amount);

    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Allows users to deposit and mint rebase tokens in return.
     */
    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getCurrentInterestrate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);

        emit Vault__Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their rebase tokens for ETH in return.
     * @param _amount Amount of tokens to redeem.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }

        i_rebaseToken.burn(msg.sender, _amount);

        // payable(msg.sender).transfer(_amount); // Not good practice (?). Using low level "call" function
        (bool success,) = payable(msg.sender).call{value: _amount}("");

        if (!success) {
            revert Vault__RedeemFailed();
        }

        emit Vault__Redeemed(msg.sender, _amount);
    }

    /**
     * @notice Provides an address of rebase token.
     * @return Address of rebase token.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
