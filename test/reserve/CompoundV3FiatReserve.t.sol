// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { UFixed6 } from "@equilibria/root/number/types/UFixed6.sol";
import { DSU } from "@emptyset/dsu/contracts/DSU.sol";
import { ICompoundV3FiatReserve } from "@emptyset/reserve/contracts/interfaces/strategy/ICompoundV3FiatReserve.sol";
import { CompoundV3FiatReserve } from "@emptyset/reserve/contracts/reserve/strategy/CompoundV3FiatReserve.sol";
import { MockCompoundV3Market } from "../mocks/MockCompoundV3Market.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract CompoundV3FiatReserveTest is Test {
    DSU private dsu;
    MockERC20 private usdc;
    MockERC20 private unsupportedToken;
    MockCompoundV3Market private compound;
    CompoundV3FiatReserve private reserve;

    address private user = makeAddr("user");
    address private coordinator = makeAddr("coordinator");

    function setUp() public {
        dsu = new DSU();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        unsupportedToken = new MockERC20("Uniswap", "UNI", 18);
        compound = new MockCompoundV3Market(Token6.wrap(address(usdc)));
        reserve = new CompoundV3FiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)), compound);

        dsu.transferOwnership(address(reserve));
        reserve.initialize();

        usdc.mint(user, 1000e6);
        usdc.mint(address(reserve), 100e6);

        vm.prank(user);
        usdc.approve(address(reserve), type(uint256).max);
        vm.prank(user);
        dsu.approve(address(reserve), type(uint256).max);

        reserve.updateCoordinator(coordinator);
    }

    function testConstructor() public {
        assertEq(Token18.unwrap(reserve.dsu()), address(dsu));
        assertEq(Token6.unwrap(reserve.fiat()), address(usdc));
        assertEq(address(reserve.compound()), address(compound));
    }

    function testConstructorRevertsIfMarketBaseTokenDoesNotMatchFiat() public {
        MockCompoundV3Market invalidCompound = new MockCompoundV3Market(Token6.wrap(address(unsupportedToken)));

        vm.expectRevert(ICompoundV3FiatReserve.CompoundV3FiatReserveInvalidMarketError.selector);
        new CompoundV3FiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)), invalidCompound);
    }

    function testInitializeApprovesCompound() public {
        assertEq(usdc.allowance(address(reserve), address(compound)), type(uint256).max);
    }

    function testMintWithZeroAllocationLeavesAssetsUnallocated() public {
        updateAllocation(0);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 110e6);
        assertEq(UFixed6.unwrap(compound.balanceOf(address(reserve))), 0);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
    }

    function testMintWithHalfAllocationDepositsTargetAssets() public {
        updateAllocation(0.5 ether);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 55e6);
        assertEq(UFixed6.unwrap(compound.balanceOf(address(reserve))), 55e6);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
    }

    function testMintWithFullAllocationDepositsAllAssets() public {
        updateAllocation(1 ether);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 0);
        assertEq(UFixed6.unwrap(compound.balanceOf(address(reserve))), 110e6);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
    }

    function testRedeemWithHalfAllocationWithdrawsToTarget() public {
        updateAllocation(0.5 ether);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(20 ether));

        vm.prank(user);
        reserve.redeem(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 55e6);
        assertEq(UFixed6.unwrap(compound.balanceOf(address(reserve))), 55e6);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
        assertEq(dsu.totalSupply(), 10 ether);
    }

    function updateAllocation(uint256 allocation) private {
        vm.prank(coordinator);
        reserve.updateAllocation(UFixed18.wrap(allocation));
    }
}
