// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author Zhernovkov Maxim
 * @notice This is a cross-chain rebase token that incentivices users to deposit into the vault and accrue interest.
 * @notice The interest rate in this contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20 {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    event RebaseToken_InterestRateSet(uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;

    uint256 private s_interestRate = 5e10; // Represents 0.000005% per second (because the base is 10^18, we get the "real" decimal as 5e10 / 1e18 * 100)
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastUpdatedTimestamp) private s_userLastUpdatedTimestamp;

    constructor() ERC20("Rebase Token", "RBT") {}

    /**
     * @notice Sets the new interest rate that cannot be more than the old one.
     * @param _newInterestRate New interest rate value.
     * @dev If the new interest rate is more than the old one then the function will revert.
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }

        s_interestRate = _newInterestRate;
        emit RebaseToken_InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Returns the number of tokens currently minted for the user not counting the accrued interest since last protocol interaction.
     * @param _user User to get the balance of.
     * @return Amount of minted tokens for the user.
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint tokens to the user when they deposit to the vault.
     * @param _to The user address to which the tokens will be minted.
     * @param _amount Amount of tokens to mint for the user.
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;

        // No need to emit events here ourselves, because _mint will emit an event.
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault.
     * @param _from User address.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external {
        // This is a "dust" mitigation logic, so that if the user wanted to burn all of their tokens we will do that
        // and there will be no accrued interest leftover that was accrued while the transaction was confirming.
        // This is standard practice that is used in protocol like AAVE, for example.
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice This is a modified transfer function to take into consideration accrued interests of users and also transfer interest rate to the user if they never deposited before.
     * @param _recipient The address to send tokens to.
     * @param _amount The amount of tokns to send.
     * @return True if the transfer was successful.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice This is a modified transferFrom function to take into consideration accrued interests of users and also transfer interest rate to the user if they never deposited before.
     * @param _sender The address that is sending tokens.
     * @param _recipient The address to send tokens to.
     * @param _amount The amount of tokns to send.
     * @return True if the transfer was successful.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the balance of the user including the interest since the last update.
     * @param _user The user address.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestFactorSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Adds accrued interest to the user balance since the last time they've interacted with the protocol.
     * @param _user The user address.
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;
        s_userLastUpdatedTimestamp[_user] = block.timestamp;

        // No need to emit events here ourselves, because _mint will emit an event.
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Calculates accumulated interest factor since last update for the user based on their interest rate per second.
     * @param _user The user address.
     */
    function _calculateUserAccumulatedInterestFactorSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];

        linearInterest = PRECISION_FACTOR + s_userInterestRate[_user] * timeElapsed;
    }

    /**
     * @notice Gets the interest rate for the user.
     * @param _user Address of the user.
     * @return The interest rate for the user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the current global interest rate for the protocol.
     */
    function getCurrentInterestrate() external view returns (uint256) {
        return s_interestRate;
    }
}
