// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin public dsc;

    address public owner;
    address public user;
    address public zeroAddress = address(0);

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant MINT_AMOUNT = 100 ether;
    uint256 public constant BURN_AMOUNT = 50 ether;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        vm.deal(owner, INITIAL_BALANCE);
        vm.deal(user, INITIAL_BALANCE);
        
        // Deploy the contract
        dsc = new DecentralizedStableCoin();
    }

    /* Constructor Tests */
    function testConstructorInitialization() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.decimals(), 18);
        assertEq(dsc.totalSupply(), 0);
        assertEq(dsc.owner(), owner);
    }

    /* Mint Tests */
    function testMintAsOwner() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user, MINT_AMOUNT);
        
        bool success = dsc.mint(user, MINT_AMOUNT);
        
        assertTrue(success);
        assertEq(dsc.balanceOf(user), MINT_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT);
    }

    function testMintFailsForNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        dsc.mint(user, MINT_AMOUNT);
        vm.stopPrank();
        
        assertEq(dsc.balanceOf(user), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    function testMintFailsForZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(zeroAddress, MINT_AMOUNT);
        
        assertEq(dsc.totalSupply(), 0);
    }

    function testMintFailsForZeroAmount() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(user, 0);
        
        assertEq(dsc.balanceOf(user), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    /* Burn Tests */
    function testBurnAsOwner() public {
        // First mint some tokens
        dsc.mint(owner, MINT_AMOUNT);
        assertEq(dsc.balanceOf(owner), MINT_AMOUNT);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, address(0), BURN_AMOUNT);
        
        dsc.burn(BURN_AMOUNT);
        
        assertEq(dsc.balanceOf(owner), MINT_AMOUNT - BURN_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT - BURN_AMOUNT);
    }

    function testBurnFailsForNonOwner() public {
        // Mint tokens to user
        dsc.mint(user, MINT_AMOUNT);
        
        // User tries to burn
        vm.startPrank(user);
        vm.expectRevert();
        dsc.burn(BURN_AMOUNT);
        vm.stopPrank();
        
        // Balance remains unchanged
        assertEq(dsc.balanceOf(user), MINT_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT);
    }

    function testBurnFailsForZeroAmount() public {
        dsc.mint(owner, MINT_AMOUNT);
        
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
        
        assertEq(dsc.balanceOf(owner), MINT_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT);
    }

    function testBurnFailsIfAmountExceedsBalance() public {
        dsc.mint(owner, MINT_AMOUNT);
        
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(MINT_AMOUNT + 1);
        
        assertEq(dsc.balanceOf(owner), MINT_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT);
    }

    /* Standard ERC20 Functionality Tests */
    function testTransfer() public {
        dsc.mint(owner, MINT_AMOUNT);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user, BURN_AMOUNT);
        
        bool success = dsc.transfer(user, BURN_AMOUNT);
        
        assertTrue(success);
        assertEq(dsc.balanceOf(owner), MINT_AMOUNT - BURN_AMOUNT);
        assertEq(dsc.balanceOf(user), BURN_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT);
    }

    function testApproveAndTransferFrom() public {
        dsc.mint(owner, MINT_AMOUNT);
        
        dsc.approve(user, BURN_AMOUNT);
        assertEq(dsc.allowance(owner, user), BURN_AMOUNT);
        
        vm.startPrank(user);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user, BURN_AMOUNT);
        
        bool success = dsc.transferFrom(owner, user, BURN_AMOUNT);
        
        assertTrue(success);
        assertEq(dsc.balanceOf(owner), MINT_AMOUNT - BURN_AMOUNT);
        assertEq(dsc.balanceOf(user), BURN_AMOUNT);
        assertEq(dsc.totalSupply(), MINT_AMOUNT);
        assertEq(dsc.allowance(owner, user), 0);
        
        vm.stopPrank();
    }

    /* Ownership Tests */
    function testOwnershipTransfer() public {
        assertEq(dsc.owner(), owner);
        
        dsc.transferOwnership(user);
        assertEq(dsc.owner(), user);
        
        // Now only user can mint
        vm.startPrank(user);
        bool success = dsc.mint(user, MINT_AMOUNT);
        assertTrue(success);
        vm.stopPrank();
        
        // Owner can no longer mint
        vm.expectRevert();
        dsc.mint(owner, MINT_AMOUNT);
    }

    /* Fuzz Tests */
    function testFuzz_MintWithValidAmount(uint256 amount) public {
        vm.assume(amount > 0);
        
        bool success = dsc.mint(user, amount);
        
        assertTrue(success);
        assertEq(dsc.balanceOf(user), amount);
        assertEq(dsc.totalSupply(), amount);
    }

    function testFuzz_BurnWithValidAmount(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount <= mintAmount);
        
        dsc.mint(owner, mintAmount);
        dsc.burn(burnAmount);
        
        assertEq(dsc.balanceOf(owner), mintAmount - burnAmount);
        assertEq(dsc.totalSupply(), mintAmount - burnAmount);
    }
}