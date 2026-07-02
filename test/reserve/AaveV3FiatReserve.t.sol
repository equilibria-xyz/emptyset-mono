// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { DSU } from "@emptyset/dsu/contracts/DSU.sol";
import { IAaveV3FiatReserve } from "@emptyset/reserve/contracts/interfaces/strategy/IAaveV3FiatReserve.sol";
import { AaveV3FiatReserve } from "@emptyset/reserve/contracts/reserve/strategy/AaveV3FiatReserve.sol";
import { MockAaveV3Pool } from "../mocks/MockAaveV3Pool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract AaveV3FiatReserveTest is Test {
    DSU private dsu;
    MockERC20 private usdc;
    MockERC20 private unsupportedToken;
    MockAaveV3Pool private aave;
    MockERC20 private aToken;
    AaveV3FiatReserve private reserve;

    address private user = makeAddr("user");
    address private coordinator = makeAddr("coordinator");

    function setUp() public {
        dsu = new DSU();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        unsupportedToken = new MockERC20("Uniswap", "UNI", 18);
        aave = new MockAaveV3Pool(Token6.wrap(address(usdc)));
        aToken = aave.aToken();
        reserve = new AaveV3FiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)), aave);

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
        assertEq(address(reserve.aave()), address(aave));
        assertEq(Token6.unwrap(reserve.aToken()), address(aToken));
    }

    function testConstructorRevertsIfPoolDoesNotSupportFiat() public {
        vm.expectRevert(IAaveV3FiatReserve.AaveV3FiatReserveInvalidPoolError.selector);
        new AaveV3FiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(unsupportedToken)), aave);
    }

    function testInitializeApprovesAave() public {
        assertEq(usdc.allowance(address(reserve), address(aave)), type(uint256).max);
    }

    function testMintWithZeroAllocationLeavesAssetsUnallocated() public {
        updateAllocation(0);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 110e6);
        assertEq(aToken.balanceOf(address(reserve)), 0);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
    }

    function testMintWithHalfAllocationDepositsTargetAssets() public {
        updateAllocation(0.5 ether);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 55e6);
        assertEq(aToken.balanceOf(address(reserve)), 55e6);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
    }

    function testMintWithFullAllocationDepositsAllAssets() public {
        updateAllocation(1 ether);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), 990e6);
        assertEq(usdc.balanceOf(address(reserve)), 0);
        assertEq(aToken.balanceOf(address(reserve)), 110e6);
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
        assertEq(aToken.balanceOf(address(reserve)), 55e6);
        assertEq(UFixed18.unwrap(reserve.assets()), 110 ether);
        assertEq(dsu.balanceOf(user), 10 ether);
        assertEq(dsu.totalSupply(), 10 ether);
    }

    function updateAllocation(uint256 allocation) private {
        vm.prank(coordinator);
        reserve.updateAllocation(UFixed18.wrap(allocation));
    }
}
