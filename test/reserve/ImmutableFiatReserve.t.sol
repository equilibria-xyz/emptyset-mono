// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { DSU } from "@emptyset/dsu/contracts/DSU.sol";
import { NoopFiatReserve } from "@emptyset/reserve/contracts/reserve/NoopFiatReserve.sol";
import { ImmutableFiatReserve } from "@emptyset/reserve/contracts/reserve/ImmutableFiatReserve.sol";
import { OwnableStub } from "@emptyset/reserve/contracts/utils/OwnableStub.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract ImmutableFiatReserveTest is Test {
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    DSU private dsu;
    MockERC20 private usdc;
    NoopFiatReserve private noopImplementation;
    ImmutableFiatReserve private immutableImplementation;
    ImmutableFiatReserve private reserve;
    ProxyAdmin private proxyAdmin;
    ITransparentUpgradeableProxy private proxy;

    address private user = makeAddr("user");

    function setUp() public {
        dsu = new DSU();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        noopImplementation = new NoopFiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)));
        immutableImplementation = new ImmutableFiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)));
        proxyAdmin = new ProxyAdmin();
        proxy = ITransparentUpgradeableProxy(
            address(new TransparentUpgradeableProxy(address(noopImplementation), address(proxyAdmin), ""))
        );
        reserve = ImmutableFiatReserve(address(proxy));

        dsu.transferOwnership(address(proxy));
        vm.prank(address(proxy));
        dsu.acceptOwnership();

        usdc.mint(user, 1000e6);
        vm.startPrank(user);
        usdc.approve(address(proxy), type(uint256).max);
        dsu.approve(address(proxy), type(uint256).max);
        vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(Token18.unwrap(immutableImplementation.dsu()), address(dsu));
        assertEq(Token6.unwrap(immutableImplementation.fiat()), address(usdc));
    }

    function testUpgradeAndFinalizeAtomically() public {
        address oldAdmin = _admin();

        _upgradeAndFinalize();

        address newAdmin = _admin();
        assertEq(_implementation(), address(immutableImplementation));
        assertNotEq(newAdmin, oldAdmin);
        assertGt(newAdmin.code.length, 0);
        assertEq(newAdmin.codehash, keccak256(type(OwnableStub).runtimeCode));
        assertEq(dsu.owner(), address(proxy));
    }

    function testFinalizeIsPermissionless() public {
        _upgrade();

        vm.prank(user);
        reserve.finalize();

        assertEq(_admin().codehash, keccak256(type(OwnableStub).runtimeCode));
    }

    function testFinalizeIsIdempotent() public {
        _upgradeAndFinalize();
        address finalizedAdmin = _admin();

        vm.prank(user);
        reserve.finalize();

        assertEq(_admin(), finalizedAdmin);
    }

    function testPreviousAdminCannotUpgradeAfterFinalize() public {
        _upgradeAndFinalize();
        NoopFiatReserve replacement = new NoopFiatReserve(Token18.wrap(address(dsu)), Token6.wrap(address(usdc)));

        vm.expectRevert();
        proxyAdmin.upgrade(proxy, address(replacement));

        assertEq(_implementation(), address(immutableImplementation));
    }

    function testMintRevertsWithoutPullingFiat() public {
        _upgradeAndFinalize();
        uint256 userUsdc = usdc.balanceOf(user);
        uint256 reserveUsdc = usdc.balanceOf(address(proxy));
        uint256 allowance = usdc.allowance(user, address(proxy));

        vm.prank(user);
        vm.expectRevert(NoopFiatReserve.NotImplementedError.selector);
        reserve.mint(UFixed18.wrap(10 ether));

        assertEq(usdc.balanceOf(user), userUsdc);
        assertEq(usdc.balanceOf(address(proxy)), reserveUsdc);
        assertEq(usdc.allowance(user, address(proxy)), allowance);
        assertEq(dsu.balanceOf(user), 0);
        assertEq(dsu.totalSupply(), 0);
    }

    function testRedeemBurnsDsuAndReturnsFiatAfterFinalize() public {
        vm.prank(user);
        NoopFiatReserve(address(proxy)).mint(UFixed18.wrap(10 ether));
        _upgradeAndFinalize();

        vm.prank(user);
        UFixed18 redemptionAmount = reserve.redeem(UFixed18.wrap(10 ether));

        assertEq(UFixed18.unwrap(redemptionAmount), 10 ether);
        assertEq(usdc.balanceOf(user), 1000e6);
        assertEq(usdc.balanceOf(address(proxy)), 0);
        assertEq(dsu.balanceOf(user), 0);
        assertEq(dsu.totalSupply(), 0);
        assertEq(dsu.owner(), address(proxy));
    }

    function testUpgradeAndFinalizePreservesReserveState() public {
        vm.prank(user);
        NoopFiatReserve(address(proxy)).mint(UFixed18.wrap(11 ether));

        _upgradeAndFinalize();

        assertEq(usdc.balanceOf(address(proxy)), 11e6);
        assertEq(dsu.balanceOf(user), 11 ether);
        assertEq(dsu.totalSupply(), 11 ether);
        assertEq(UFixed18.unwrap(reserve.assets()), 11 ether);
        assertEq(UFixed18.unwrap(reserve.mintPrice()), 1 ether);
        assertEq(UFixed18.unwrap(reserve.redeemPrice()), 1 ether);
    }

    function testIssueReverts() public {
        _upgradeAndFinalize();

        vm.expectRevert(NoopFiatReserve.NotImplementedError.selector);
        reserve.issue(UFixed18.wrap(1 ether));
    }

    function _upgrade() private {
        proxyAdmin.upgrade(proxy, address(immutableImplementation));
    }

    function _upgradeAndFinalize() private {
        proxyAdmin.upgradeAndCall(
            proxy,
            address(immutableImplementation),
            abi.encodeCall(ImmutableFiatReserve.finalize, ())
        );
    }

    function _implementation() private view returns (address) {
        return address(uint160(uint256(vm.load(address(proxy), IMPLEMENTATION_SLOT))));
    }

    function _admin() private view returns (address) {
        return address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
    }
}
