// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        uint256 startingRebaseTokenBalance = rebaseToken.balanceOf(user);
        assertEq(amount, startingRebaseTokenBalance);
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startingRebaseTokenBalance);
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        // This is because there is a 1 wei loss in difference because the way math works in Solidity :| So we need to add that to the tolerance
        assertApproxEqAbs(middleBalance - startingRebaseTokenBalance, endBalance - middleBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(amount, rebaseToken.balanceOf(user));
        vault.redeem(type(uint256).max);
        assertEq(0, rebaseToken.balanceOf(user));
        assertEq(amount, user.balance);
        vm.stopPrank();
    }

    function testRedeemBalanceAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint32).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        vm.warp(block.timestamp + time);
        uint256 balance = rebaseToken.balanceOf(user);
        uint256 rewards = balance - depositAmount;
        vm.deal(owner, rewards);
        vm.prank(owner);
        addRewardsToVault(rewards);
        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = user.balance;
        assertEq(ethBalance, balance);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2 * 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        assertEq(amount, userBalance);
        assertEq(0, user2Balance);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(amountToSend, user2BalanceAfterTransfer);
        assertEq(userBalance - amountToSend, userBalanceAfterTransfer);
        assertEq(5e10, rebaseToken.getUserInterestRate(user));
        assertEq(5e10, rebaseToken.getUserInterestRate(user2));
    }

    function testCannotSetInterestIfNotOwner(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        uint256 interestRate = rebaseToken.getCurrentInterestrate();
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100, interestRate);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 100);
    }

    function testCanGetPrincipalAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        assertEq(amount, rebaseToken.principalBalanceOf(user));

        vm.warp(block.timestamp + 1 hours);

        assertEq(amount, rebaseToken.principalBalanceOf(user));
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(address(rebaseToken), vault.getRebaseTokenAddress());
    }

    function testDepositAndRedeemEmitsEvent() public {
        uint256 amount = 1e5;

        vm.startPrank(user);
        vm.deal(user, amount);

        vm.expectEmit(true, true, true, true);
        emit Vault.Vault__Deposit(user, amount);

        vault.deposit{value: amount}();

        vm.expectEmit(true, true, true, true);
        emit Vault.Vault__Redeemed(user, amount);

        vault.redeem(type(uint256).max);
        vm.stopPrank();
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getCurrentInterestrate();
        newInterestRate = bound(newInterestRate, initialInterestRate + 1, type(uint256).max);

        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);

        assertEq(initialInterestRate, rebaseToken.getCurrentInterestrate());
    }
}
