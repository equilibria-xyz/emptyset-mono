// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { IOwnable } from "@equilibria/root/attribute/interfaces/IOwnable.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { DSU } from "@emptyset/dsu/contracts/DSU.sol";
import { IReserve } from "@emptyset/reserve/contracts/interfaces/IReserve.sol";
import { IReserveBase } from "@emptyset/reserve/contracts/interfaces/IReserveBase.sol";
import { NoopFiatReserve } from "@emptyset/reserve/contracts/reserve/strategy/NoopFiatReserve.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract NoopFiatReserveTest is Test {
    DSU private dsu;
    MockERC20 private usdc;
    NoopFiatReserve private reserve;

    address private user = makeAddr("user");
    address private coordinator = makeAddr("coordinator");

    function setUp() public {
        dsu = new DSU();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        reserve = new NoopFiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)));

        dsu.transferOwnership(address(reserve));
        reserve.initialize();

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

    function testInitializeDoesNothingIfAlreadyDsuOwner() public {
        DSU newDsu = new DSU();
        NoopFiatReserve newReserve = new NoopFiatReserve(Token18.wrap(address(newDsu)), Token6.wrap(address(usdc)));

        newDsu.transferOwnership(address(newReserve));
        vm.prank(address(newReserve));
        newDsu.acceptOwnership();

        newReserve.initialize();

        assertEq(newDsu.owner(), address(newReserve));
        assertEq(newReserve.owner(), address(this));
    }

    function testInitializeDoesNothingIfAlreadyHasOwner() public {
        DSU newDsu = new DSU();
        NoopFiatReserve newReserve = new NoopFiatReserve(Token18.wrap(address(newDsu)), Token6.wrap(address(usdc)));

        vm.prank(address(0));
        newReserve.updatePendingOwner(address(this));
        newReserve.acceptOwner();
        newDsu.transferOwnership(address(newReserve));

        vm.prank(user);
        newReserve.initialize();

        assertEq(newReserve.owner(), address(this));
        assertEq(newDsu.owner(), address(newReserve));
    }

    function testInitializeAcceptsDsuOwnership() public {
        DSU newDsu = new DSU();
        NoopFiatReserve newReserve = new NoopFiatReserve(Token18.wrap(address(newDsu)), Token6.wrap(address(usdc)));
        newDsu.transferOwnership(address(newReserve));

        newReserve.initialize();

        assertEq(newDsu.owner(), address(newReserve));
    }

    function testInitializeRevertsIfReserveIsNotPendingDsuOwner() public {
        DSU newDsu = new DSU();
        NoopFiatReserve newReserve = new NoopFiatReserve(Token18.wrap(address(newDsu)), Token6.wrap(address(usdc)));

        vm.expectRevert("Ownable2Step: caller is not the new owner");
        newReserve.initialize();
    }

    function testUpdateCoordinator() public {
        reserve.updateCoordinator(coordinator);

        assertEq(reserve.coordinator(), coordinator);
    }

    function testUpdateCoordinatorRevertsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IOwnable.OwnableNotOwnerError.selector, user));
        vm.prank(user);
        reserve.updateCoordinator(coordinator);

        assertEq(reserve.coordinator(), address(0));
    }

    function testUpdateAllocation() public {
        reserve.updateCoordinator(coordinator);

        vm.prank(coordinator);
        reserve.updateAllocation(UFixed18.wrap(0.5 ether));

        assertEq(UFixed18.unwrap(reserve.allocation()), 0.5 ether);
    }

    function testUpdateAllocationRevertsIfTooLarge() public {
        reserve.updateCoordinator(coordinator);

        vm.expectRevert(IReserveBase.ReserveBaseInvalidAllocationError.selector);
        vm.prank(coordinator);
        reserve.updateAllocation(UFixed18.wrap(1 ether + 1));
    }

    function testUpdateAllocationRevertsIfNotCoordinator() public {
        vm.expectRevert(IReserveBase.ReserveBaseNotCoordinatorError.selector);
        vm.prank(user);
        reserve.updateAllocation(UFixed18.wrap(0.5 ether));
    }

    function testPricesReturnOne() public {
        assertEq(UFixed18.unwrap(reserve.mintPrice()), 1 ether);
        assertEq(UFixed18.unwrap(reserve.redeemPrice()), 1 ether);
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

    function testIssueMintsDsuUpToCollateralRequirement() public {
        usdc.mint(address(reserve), 10e6);

        reserve.issue(UFixed18.wrap(10 ether));

        assertEq(dsu.balanceOf(address(this)), 10 ether);
        assertEq(dsu.totalSupply(), 10 ether);
        assertEq(UFixed18.unwrap(reserve.assets()), 10 ether);
    }

    function testIssueRevertsIfUnderCollateralized() public {
        usdc.mint(address(reserve), 10e6);

        vm.expectRevert(IReserve.ReserveBaseInsufficientAssetsError.selector);
        reserve.issue(UFixed18.wrap(11 ether));
    }

    function testIssueRevertsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IOwnable.OwnableNotOwnerError.selector, user));
        vm.prank(user);
        reserve.issue(UFixed18.wrap(10 ether));
    }
}
