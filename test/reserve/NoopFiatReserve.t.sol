// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { DSU } from "@emptyset/dsu/contracts/DSU.sol";
import { NoopFiatReserve } from "@emptyset/reserve/contracts/reserve/NoopFiatReserve.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract NoopFiatReserveTest is Test {
    DSU private dsu;
    MockERC20 private usdc;
    NoopFiatReserve private reserve;

    address private user = makeAddr("user");

    function setUp() public {
        dsu = new DSU();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        reserve = new NoopFiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)));

        dsu.transferOwnership(address(reserve));
        vm.prank(address(reserve));
        dsu.acceptOwnership();

        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(reserve), type(uint256).max);
        vm.prank(user);
        dsu.approve(address(reserve), type(uint256).max);
    }

    function testConstructor() public {
        assertEq(Token18.unwrap(reserve.dsu()), address(dsu));
        assertEq(Token6.unwrap(reserve.fiat()), address(usdc));
    }

    function testPricesReturnOne() public {
        assertEq(UFixed18.unwrap(reserve.mintPrice()), 1 ether);
        assertEq(UFixed18.unwrap(reserve.redeemPrice()), 1 ether);
    }

    function testAssetsReturnsFiatBalance() public {
        usdc.mint(address(reserve), 123e6);

        assertEq(UFixed18.unwrap(reserve.assets()), 123 ether);
    }

    function testMintPullsUsdcAndMintsDsu() public {
        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 10e6);
        assertEq(dsu.balanceOf(user), 10 ether);
        assertEq(dsu.totalSupply(), 10 ether);
        assertEq(UFixed18.unwrap(reserve.assets()), 10 ether);
    }

    function testMintRoundsUsdcOut() public {
        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether - 1));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(dsu.balanceOf(user), 10 ether - 1);
        assertEq(UFixed18.unwrap(reserve.assets()), 10 ether);
    }

    function testRedeemPullsDsuAndPushesUsdc() public {
        vm.prank(user);
        reserve.mint(UFixed18.wrap(11 ether));

        vm.prank(user);
        reserve.redeem(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 999e6);
        assertEq(usdc.balanceOf(address(reserve)), 1e6);
        assertEq(dsu.balanceOf(user), 1 ether);
        assertEq(dsu.totalSupply(), 1 ether);
        assertEq(UFixed18.unwrap(reserve.assets()), 1 ether);
    }

    function testRedeemRoundsUsdcIn() public {
        vm.prank(user);
        reserve.mint(UFixed18.wrap(11 ether));

        vm.prank(user);
        reserve.redeem(UFixed18.wrap(10 ether + 1));

        assertEq(usdc.balanceOf(user), 999e6);
        assertEq(dsu.balanceOf(user), 1 ether - 1);
        assertEq(dsu.totalSupply(), 1 ether - 1);
        assertEq(UFixed18.unwrap(reserve.assets()), 1 ether);
    }

    function testRedeemRevertsIfReserveLacksFiat() public {
        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        vm.prank(address(reserve));
        usdc.transfer(user, 5e6);

        vm.prank(user);
        vm.expectRevert();
        reserve.redeem(UFixed18.wrap(10 ether));
    }

    function testIssueReverts() public {
        vm.expectRevert(NoopFiatReserve.NotImplementedError.selector);
        reserve.issue(UFixed18.wrap(1 ether));
    }
}
