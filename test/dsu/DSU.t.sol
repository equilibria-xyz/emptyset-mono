// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { DSU } from "@emptyset/dsu/contracts/DSU.sol";

contract DSUTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    DSU private dsu;
    address private user = makeAddr("user");

    function setUp() public {
        dsu = new DSU();
    }

    function testMintMintsToSender() public {
        uint256 amount = 10 ether;

        vm.expectEmit(true, true, true, true, address(dsu));
        emit Transfer(address(0), address(this), amount);

        dsu.mint(amount);

        assertEq(dsu.balanceOf(address(this)), amount);
    }

    function testMintRevertsIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        dsu.mint(10 ether);
    }

    function testBurnBurnsFromSender() public {
        uint256 amount = 10 ether;
        dsu.mint(amount);

        vm.expectEmit(true, true, true, true, address(dsu));
        emit Transfer(address(this), address(0), amount);

        dsu.burn(amount);

        assertEq(dsu.balanceOf(address(this)), 0);
    }

    function testBurnRevertsIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        dsu.burn(10 ether);
    }
}
