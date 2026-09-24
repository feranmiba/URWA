// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {URWA} from "../src/MyToken.sol";

contract URWATest is Test {
    URWA public token;

    address public owner = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xCAFE);

    // Events matching URWA
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Frozen(address indexed account, uint256 amount);
    event unFrozen(address indexed account, uint256 amount);
    event forcedTransferSuccess(address indexed from, address indexed to, uint256 amount, uint256 fromBalance, uint256 fromFrozen);

    function setUp() public {
        token = new URWA();
    }

    /* -------------------------------------------------------------------------- */
    /*                               INITIAL STATE                                */
    /* -------------------------------------------------------------------------- */

    function test_InitialState() public view {
        assertEq(token.name(), "URWA-AMIOLA");
        assertEq(token.symbol(), "URWA");
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(token.balanceOf(owner), 1_000_000_000 * 10 ** 18);
        assertTrue(token.allowList(owner));
        assertFalse(token.allowList(alice));
    }

    /* -------------------------------------------------------------------------- */
    /*                              ALLOWLIST TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_AddToAllowList_Success() public {
        token.addToAllowList(alice);
        assertTrue(token.allowList(alice));
    }

    function test_RemoveFromAllowList_Success() public {
        token.addToAllowList(alice);
        assertTrue(token.allowList(alice));

        token.removeFromAllowList(alice);
        assertFalse(token.allowList(alice));
    }

    function test_AllowList_RevertIf_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(URWA.NotOwner.selector);
        token.addToAllowList(bob);

        vm.prank(alice);
        vm.expectRevert(URWA.NotOwner.selector);
        token.removeFromAllowList(bob);
    }

    /* -------------------------------------------------------------------------- */
    /*                               TRANSFER TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_Transfer_Success() public {
        token.addToAllowList(alice);

        uint256 amount = 1000 * 10 ** 18;
        uint256 ownerInitial = token.balanceOf(owner);

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, alice, amount);

        bool success = token.transfer(alice, amount);
        assertTrue(success);

        assertEq(token.balanceOf(owner), ownerInitial - amount);
        assertEq(token.balanceOf(alice), amount);
    }

    function test_Transfer_RevertIf_SenderNotAllowlisted() public {
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);

        // Remove alice from allowList
        token.removeFromAllowList(alice);
        token.addToAllowList(bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(URWA.ERC7943CannotSend.selector, alice));
        token.transfer(bob, 100 * 10 ** 18);
    }

    function test_Transfer_RevertIf_ReceiverNotAllowlisted() public {
        uint256 amount = 500 * 10 ** 18;

        // Alice is NOT in allowList
        vm.expectRevert(abi.encodeWithSelector(URWA.ERC7943CannotReceive.selector, alice));
        token.transfer(alice, amount);
    }

    function test_Transfer_RevertIf_InsufficientBalance() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);

        token.transfer(alice, 100 * 10 ** 18);

        // Alice tries to send more than balance
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 100 * 10 ** 18, 200 * 10 ** 18));
        token.transfer(bob, 200 * 10 ** 18);
    }

    function test_Transfer_RevertIf_InsufficientAvailableBalanceDueToFrozen() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);
        token.transfer(alice, 1000 * 10 ** 18);

        // Freeze alice tokens (freezeByAddress requires allowList[account] == true)
        token.freezeByAddress(alice);

        // Available balance becomes 0
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 0, 100 * 10 ** 18));
        token.transfer(bob, 100 * 10 ** 18);
    }

    function test_Transfer_RevertIf_AmountExceedsMaxTokens() public {
        token.addToAllowList(alice);
        uint256 max = token.MAX_TOKENS();

        // Note: checkGuardBalance checks available balance first, reverting with InsufficientBalance
        // if amount exceeds available balance (which is at most MAX_TOKENS)
        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, max, max + 1));
        token.transfer(alice, max + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                         APPROVE & TRANSFERFROM TESTS                       */
    /* -------------------------------------------------------------------------- */

    function test_Approve_Success() public {
        uint256 amount = 500 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit Approval(owner, alice, amount);

        token.approve(alice, amount);
        assertEq(token.allowance(owner, alice), amount);
    }

    function test_TransferFrom_Success() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);

        uint256 amount = 500 * 10 ** 18;
        token.approve(alice, amount);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, bob, amount);

        bool success = token.transferFrom(owner, bob, amount);
        assertTrue(success);

        assertEq(token.allowance(owner, alice), 0);
        assertEq(token.balanceOf(bob), amount);
    }

    function test_TransferFrom_RevertIf_InsufficientAllowance() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);

        token.approve(alice, 100 * 10 ** 18);

        vm.prank(alice);
        // checkGuardBalance is called on allowance, returning InsufficientBalance
        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 100 * 10 ** 18, 200 * 10 ** 18));
        token.transferFrom(owner, bob, 200 * 10 ** 18);
    }

    function test_TransferFrom_RevertIf_InsufficientBalance() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);

        // Give alice 50 tokens
        token.transfer(alice, 50 * 10 ** 18);

        // Alice approves Bob for 100 tokens (more than her balance)
        vm.prank(alice);
        token.approve(bob, 100 * 10 ** 18);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 50 * 10 ** 18, 100 * 10 ** 18));
        token.transferFrom(alice, bob, 100 * 10 ** 18);
    }

    /* -------------------------------------------------------------------------- */
    /*                              FREEZING TESTS                                */
    /* -------------------------------------------------------------------------- */

    function test_FreezeByAddress_Success() public {
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);

        vm.expectEmit(true, false, false, true);
        emit Frozen(alice, 1000 * 10 ** 18);

        bool success = token.freezeByAddress(alice);
        assertTrue(success);
        assertEq(token.frozenTokens(alice), 1000 * 10 ** 18);
    }

    function test_FreezeByAddress_RevertIf_NotInAllowList() public {
        // Alice is not in allowList
        vm.expectRevert(URWA.NotFound.selector);
        token.freezeByAddress(alice);
    }

    function test_FreezeByAddress_RevertIf_AlreadyFrozen() public {
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);

        token.freezeByAddress(alice);

        // Freezing again when frozenTokens == balanceOf reverts
        vm.expectRevert(abi.encodeWithSelector(URWA.AlreadyFrozen.selector, alice));
        token.freezeByAddress(alice);
    }

    function test_SetFrozenTokens_Success() public {
        // Setup alice with tokens, but NOT in allowList (allowList == false required by setFrozenTokens)
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);
        token.removeFromAllowList(alice);

        vm.expectEmit(true, false, false, true);
        emit Frozen(alice, 400 * 10 ** 18);

        bool success = token.setFrozenTokens(alice, 400 * 10 ** 18);
        assertTrue(success);
        assertEq(token.frozenTokens(alice), 400 * 10 ** 18);
    }

    function test_SetFrozenTokens_RevertIf_InAllowList() public {
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);

        // When allowList is true, setFrozenTokens reverts NotFound
        vm.expectRevert(URWA.NotFound.selector);
        token.setFrozenTokens(alice, 500 * 10 ** 18);
    }

    function test_SetFrozenTokens_RevertIf_InsufficientBalance() public {
        token.addToAllowList(alice);
        token.transfer(alice, 100 * 10 ** 18);
        token.removeFromAllowList(alice);

        // Trying to freeze 200 when balance is 100
        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 200 * 10 ** 18, 100 * 10 ** 18));
        token.setFrozenTokens(alice, 200 * 10 ** 18);
    }

    function test_UnfreezeToken_Success() public {
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);
        token.freezeByAddress(alice);

        vm.expectEmit(true, false, false, true);
        emit unFrozen(alice, 400 * 10 ** 18);

        bool success = token.unfreezeToken(alice, 400 * 10 ** 18);
        assertTrue(success);
        assertEq(token.frozenTokens(alice), 600 * 10 ** 18);
    }

    function test_UnfreezeToken_RevertIf_InsufficientFrozen() public {
        token.addToAllowList(alice);
        token.transfer(alice, 1000 * 10 ** 18);
        token.freezeByAddress(alice); // frozen = 1000

        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 1200 * 10 ** 18, 1000 * 10 ** 18));
        token.unfreezeToken(alice, 1200 * 10 ** 18);
    }

    /* -------------------------------------------------------------------------- */
    /*                           FORCED TRANSFER TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_ForcedTransfer_Success_WhenAmountLessThanOrEqualFrozen() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);
        token.transfer(alice, 1000 * 10 ** 18);
        token.freezeByAddress(alice); // alice balance = 1000, frozen = 1000

        uint256 amount = 400 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        // Event params: from, to, amount, fromBalance (after deduct: 600), fromFrozen (before deduct: 1000)
        emit forcedTransferSuccess(alice, bob, amount, 600 * 10 ** 18, 1000 * 10 ** 18);

        bool success = token.forcedTransfer(alice, bob, amount);
        assertTrue(success);

        assertEq(token.balanceOf(alice), 600 * 10 ** 18);
        assertEq(token.frozenTokens(alice), 600 * 10 ** 18);
        assertEq(token.balanceOf(bob), 400 * 10 ** 18);
    }

    function test_ForcedTransfer_Success_WhenAmountExceedsFrozen() public {
        token.addToAllowList(alice);
        token.addToAllowList(bob);
        token.transfer(alice, 1000 * 10 ** 18);
        token.removeFromAllowList(alice);
        token.setFrozenTokens(alice, 300 * 10 ** 18); // alice balance = 1000, frozen = 300

        uint256 amount = 500 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit forcedTransferSuccess(alice, bob, amount, 500 * 10 ** 18, 300 * 10 ** 18);

        bool success = token.forcedTransfer(alice, bob, amount);
        assertTrue(success);

        assertEq(token.balanceOf(alice), 500 * 10 ** 18);
        assertEq(token.frozenTokens(alice), 0); // resets to 0 since amount > fromFrozen
        assertEq(token.balanceOf(bob), 500 * 10 ** 18);
    }

    function test_ForcedTransfer_RevertIf_InsufficientBalance() public {
        token.addToAllowList(alice);
        token.transfer(alice, 100 * 10 ** 18);

        vm.expectRevert(abi.encodeWithSelector(URWA.InsufficientBalance.selector, 200 * 10 ** 18, 100 * 10 ** 18));
        token.forcedTransfer(alice, bob, 200 * 10 ** 18);
    }

    function test_ForcedTransfer_RevertIf_NotOwner() public {
        token.addToAllowList(alice);
        token.transfer(alice, 100 * 10 ** 18);

        vm.prank(bob);
        vm.expectRevert(URWA.NotOwner.selector);
        token.forcedTransfer(alice, bob, 50 * 10 ** 18);
    }

    function test_Freezing_NonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert(URWA.NotOwner.selector);
        token.setFrozenTokens(alice, 100);

        vm.prank(alice);
        vm.expectRevert(URWA.NotOwner.selector);
        token.unfreezeToken(alice, 100);

        vm.prank(alice);
        vm.expectRevert(URWA.NotOwner.selector);
        token.freezeByAddress(alice);
    }
}
