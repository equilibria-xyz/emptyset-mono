// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { NoopFiatReserve } from "@emptyset/reserve/contracts/reserve/NoopFiatReserve.sol";
import { L1Migrator } from "@emptyset/reserve/contracts/reserve/migration/L1Migrator.sol";
import { MockVotes } from "../mocks/MockVotes.sol";

interface IDSULike is IERC20 {
    function owner() external view returns (address);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC20MetadataLike is IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IComptrollerLike {
    function compAccrued(address account) external view returns (uint256);
    function compSpeeds(address market) external view returns (uint256);
    function compSupplySpeeds(address market) external view returns (uint256);
}

interface IGovernorLike {
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256);
    function castVote(uint256 proposalId, bool support) external;
    function queue(uint256 proposalId) external;
    function execute(uint256 proposalId) external payable;
    function proposals(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        uint256 eta,
        uint256 startBlock,
        uint256 endBlock,
        uint256 forVotes,
        uint256 againstVotes,
        bool canceled,
        bool executed
    );
    function quorumVotes() external view returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
}

contract L1MigratorMainnetTest is Test {
    address private constant RESERVE = 0xD05aCe63789cCb35B9cE71d01e4d632a0486Da4B;
    address private constant PROXY_ROOT = 0x4d2A5E3b7831156f62C8dF47604E321cdAF35fec;
    address private constant TIMELOCK = 0x1bba92F379375387bf8F927058da14D47464cB7A;
    address private constant GOVERNOR = 0x47C61a54B1d24d571F07a79d54543231292f769b;
    address private constant DSU = 0x605D26FBd5be761089281d5cec2Ce86eeA667109;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address private constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address private constant ESS = 0x24aE124c4CC33D6791F8E8B63520ed7107ac8b3e;
    address private constant TWO_WAY_BATCHER = 0xAEf566ca7E84d1E736f999765a804687f39D9094;
    address private constant WRAP_ONLY_BATCHER = 0x0B663CeaCEF01f2f88EB7451C70Aa069f19dB997;
    address private constant OLD_RESERVE_IMPL = 0x363aF3acFfEd0B7181C2E3c56C00922E142100a8;

    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant LEGACY_OWNER_SLOT = keccak256("emptyset.v2.implementation.owner");
    bytes32 private constant LEGACY_REGISTRY_SLOT = keccak256("emptyset.v2.implementation.registry");
    bytes32 private constant LEGACY_NOT_ENTERED_SLOT = keccak256("emptyset.v2.implementation.notEntered");
    bytes32 private constant LEGACY_PAUSER_SLOT = keccak256("emptyset.v2.implementation.pauser");
    bytes32 private constant LEGACY_PAUSED_SLOT = keccak256("emptyset.v2.implementation.paused");
    bytes32 private constant ROOT_OWNER_SLOT = keccak256("equilibria.root.Ownable.owner");
    bytes32 private constant ROOT_PENDING_OWNER_SLOT = keccak256("equilibria.root.Ownable.pendingOwner");
    bytes32 private constant ROOT_INITIALIZER_VERSION_SLOT = keccak256("equilibria.root.Initializable.version");
    bytes32 private constant ROOT_INITIALIZER_INITIALIZING_SLOT =
        keccak256("equilibria.root.Initializable.initializing");
    bytes32 private constant LEGACY_TOTAL_DEBT_SLOT = bytes32(uint256(0));
    bytes32 private constant LEGACY_DEBT_SLOT = bytes32(uint256(1));
    bytes32 private constant LEGACY_ORDERS_SLOT = bytes32(uint256(2));

    IGovernorLike private governor = IGovernorLike(GOVERNOR);
    IDSULike private dsu = IDSULike(DSU);
    IERC20MetadataLike private usdc = IERC20MetadataLike(USDC);
    IERC20MetadataLike private cUsdc = IERC20MetadataLike(CUSDC);
    IERC20MetadataLike private comp = IERC20MetadataLike(COMP);
    IERC20MetadataLike private ess = IERC20MetadataLike(ESS);
    IComptrollerLike private comptroller = IComptrollerLike(COMPTROLLER);

    bool private forkUnavailable;

    struct PreState {
        uint256 totalSupply;
        uint256 reserveDsu;
        uint256 reserveUsdc;
        uint256 reserveComp;
        uint256 reserveEss;
        uint256 timelockEss;
        uint256 timelockUsdc;
        uint256 essTotalSupply;
        uint256 twoWayDsu;
        uint256 twoWayUsdc;
        uint256 reserveCUsdc;
        uint256 totalDebt;
        uint256 twoWayDebt;
        uint256 wrapOnlyDebt;
    }

    struct MigrationSlots {
        bytes32 twoWayDebt;
        bytes32 wrapOnlyDebt;
        bytes32 cUsdcEssPrice;
        bytes32 cUsdcEssAmount;
        bytes32 compEssPrice;
        bytes32 compEssAmount;
    }

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_NODE_URL", string(""));
        forkUnavailable = bytes(rpc).length == 0;
        if (forkUnavailable) return;

        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK_NUMBER", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);
    }

    function testPassesGovernanceExecutesAtomicallyAndLeavesReserveInNoopState() public {
        vm.skip(forkUnavailable);

        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");
        address user = makeAddr("user");
        vm.deal(proposer, 10 ether);
        vm.deal(voter, 10 ether);

        NoopFiatReserve finalReserve = new NoopFiatReserve(Token18.wrap(DSU), Token6.wrap(USDC));
        L1Migrator migrator = new L1Migrator();
        MockVotes mockVotes = new MockVotes(governor.quorumVotes());
        vm.store(GOVERNOR, bytes32(uint256(1)), bytes32(uint256(uint160(address(mockVotes)))));

        MigrationSlots memory slots = loadMigrationSlots();
        PreState memory pre = loadPreState(slots);

        assertPreState(pre, slots);

        uint256 proposalId = proposeCleanup(proposer, pre.timelockEss, address(migrator), address(finalReserve));
        executeProposal(proposalId, proposer, voter);

        assertPostState(pre, slots, address(finalReserve));
        assertForwardReserveBehavior(user);
    }

    function loadPreState(MigrationSlots memory slots) private view returns (PreState memory pre) {
        pre.totalSupply = dsu.totalSupply();
        pre.reserveDsu = dsu.balanceOf(RESERVE);
        pre.reserveUsdc = usdc.balanceOf(RESERVE);
        pre.reserveComp = comp.balanceOf(RESERVE);
        pre.reserveEss = ess.balanceOf(RESERVE);
        pre.timelockEss = ess.balanceOf(TIMELOCK);
        pre.timelockUsdc = usdc.balanceOf(TIMELOCK);
        pre.essTotalSupply = ess.totalSupply();
        pre.twoWayDsu = dsu.balanceOf(TWO_WAY_BATCHER);
        pre.twoWayUsdc = usdc.balanceOf(TWO_WAY_BATCHER);
        pre.reserveCUsdc = cUsdc.balanceOf(RESERVE);
        pre.totalDebt = storageUint(LEGACY_TOTAL_DEBT_SLOT);
        pre.twoWayDebt = storageUint(slots.twoWayDebt);
        pre.wrapOnlyDebt = storageUint(slots.wrapOnlyDebt);
    }

    function loadMigrationSlots() private pure returns (MigrationSlots memory slots) {
        slots.twoWayDebt = mappingSlot(TWO_WAY_BATCHER, 1);
        slots.wrapOnlyDebt = mappingSlot(WRAP_ONLY_BATCHER, 1);
        (slots.cUsdcEssPrice, slots.cUsdcEssAmount) = orderSlots(CUSDC, ESS);
        (slots.compEssPrice, slots.compEssAmount) = orderSlots(COMP, ESS);
    }

    function assertPreState(PreState memory pre, MigrationSlots memory slots) private view {
        expectStorageAddress(IMPLEMENTATION_SLOT, OLD_RESERVE_IMPL);
        expectStorageAddress(LEGACY_OWNER_SLOT, TIMELOCK);
        assertEq(dsu.owner(), RESERVE);
        assertEq(comptroller.compAccrued(RESERVE), 0);
        assertEq(comptroller.compSpeeds(CUSDC), 0);
        assertEq(comptroller.compSupplySpeeds(CUSDC), 0);
        assertGt(pre.twoWayDsu, 0);
        assertGt(pre.reserveCUsdc, 0);
        assertGt(pre.reserveEss, 0);
        assertGt(pre.timelockEss, 0);
        assertGt(pre.totalDebt, 0);
        assertGt(pre.twoWayDebt, 0);
        assertEq(pre.totalDebt, pre.twoWayDebt + pre.wrapOnlyDebt);
        assertEq(pre.wrapOnlyDebt, 0);
        assertEq(dsu.balanceOf(WRAP_ONLY_BATCHER), 0);
        assertEq(usdc.balanceOf(WRAP_ONLY_BATCHER), 0);
        assertEq(IERC20(TWO_WAY_BATCHER).totalSupply(), 0);
        assertNotEq(vm.load(RESERVE, slots.cUsdcEssPrice), bytes32(0));
        assertNotEq(vm.load(RESERVE, slots.cUsdcEssAmount), bytes32(0));
        assertNotEq(vm.load(RESERVE, slots.compEssPrice), bytes32(0));
        assertNotEq(vm.load(RESERVE, slots.compEssAmount), bytes32(0));
    }

    function proposeCleanup(
        address proposer,
        uint256 timelockEss,
        address migrator,
        address finalReserve
    ) private returns (uint256) {
        address[] memory targets = new address[](3);
        targets[0] = ESS;
        targets[1] = PROXY_ROOT;
        targets[2] = PROXY_ROOT;

        uint256[] memory values = new uint256[](3);

        string[] memory signatures = new string[](3);
        signatures[0] = "transfer(address,uint256)";
        signatures[1] = "upgradeAndCall(address,address,bytes)";
        signatures[2] = "upgrade(address,address)";

        bytes[] memory calldatas = new bytes[](3);
        calldatas[0] = abi.encode(RESERVE, timelockEss);
        calldatas[1] = abi.encode(RESERVE, migrator, abi.encodeCall(L1Migrator.initialize, ()));
        calldatas[2] = abi.encode(RESERVE, finalReserve);

        vm.prank(proposer);
        return governor.propose(targets, values, signatures, calldatas, proposalDescription());
    }

    function proposalDescription() private pure returns (string memory) {
        return string.concat(
            "# DSU Reserve Cleanup (Ethereum L1)\n\n",
            "This proposal cleans up and modernizes the DSU reserve on Ethereum L1. DSU remains fully backed ",
            "and redeemable 1:1 for USDC; retired legacy integrations are permanently disabled, simplifying ",
            "future operation of the reserve.\n\n",
            "**Action 1 - ESS.transfer(Reserve, amount):** Transfer the Timelock's full ESS balance to the Reserve ",
            "so it is burned during migration.\n\n",
            "**Action 2 - ProxyRoot.upgradeAndCall(Reserve, L1Migrator, initialize()):** Atomically: redeem the ",
            "Reserve's entire cUSDC position to USDC; recall all DSU and USDC from the Two Way Batcher and clear ",
            "all batcher debt; clear the legacy cUSDC/ESS and COMP/ESS orders; burn all DSU and ESS held by the ",
            "Reserve; withdraw USDC in excess of the outstanding DSU supply to the Timelock; migrate storage to ",
            "the modern layout and clear legacy registry, pauser, and reentrancy state. The migration reverts ",
            "unless the remaining DSU total supply is fully backed by the Reserve's USDC.\n\n",
            "**Action 3 - ProxyRoot.upgrade(Reserve, NoopFiatReserve):** Set the new Reserve implementation: ",
            "1:1 USDC mint/redeem only, no strategy allocation, no debt, no orders.\n\n",
            "The Timelock retains control of the Reserve through the ProxyRoot for future governance actions."
        );
    }

    function executeProposal(uint256 proposalId, address proposer, address voter) private {
        (,, uint256 eta, uint256 startBlock, uint256 endBlock,,,,) = governor.proposals(proposalId);
        eta;
        vm.roll(startBlock + 1);
        assertEq(governor.state(proposalId), 1);

        vm.prank(voter);
        governor.castVote(proposalId, true);

        vm.roll(endBlock + 1);
        assertEq(governor.state(proposalId), 4);

        vm.prank(proposer);
        governor.queue(proposalId);
        (,, eta,,,,,,) = governor.proposals(proposalId);
        vm.warp(eta + 1);
        assertEq(governor.state(proposalId), 5);

        vm.prank(proposer);
        governor.execute(proposalId);
        assertEq(governor.state(proposalId), 7);
    }

    function assertPostState(PreState memory pre, MigrationSlots memory slots, address finalReserve) private view {
        NoopFiatReserve reserve = NoopFiatReserve(RESERVE);
        uint256 postReserveUsdc = usdc.balanceOf(RESERVE);

        expectStorageAddress(IMPLEMENTATION_SLOT, finalReserve);
        assertEq(cUsdc.balanceOf(RESERVE), 0);
        assertEq(dsu.balanceOf(RESERVE), 0);
        assertEq(dsu.balanceOf(TWO_WAY_BATCHER), 0);
        assertEq(usdc.balanceOf(TWO_WAY_BATCHER), 0);
        assertEq(dsu.totalSupply(), pre.totalSupply - pre.twoWayDsu - pre.reserveDsu);
        assertEq(ess.balanceOf(RESERVE), 0);
        assertEq(ess.balanceOf(TIMELOCK), 0);
        assertEq(ess.totalSupply(), pre.essTotalSupply - pre.reserveEss - pre.timelockEss);
        assertGe(postReserveUsdc * 1e12, dsu.totalSupply());
        assertLt(postReserveUsdc * 1e12, dsu.totalSupply() + 1e12);
        assertGt(usdc.balanceOf(TIMELOCK), pre.timelockUsdc);
        assertEq(comp.balanceOf(RESERVE), pre.reserveComp);

        expectStorageZero(LEGACY_TOTAL_DEBT_SLOT);
        expectStorageZero(LEGACY_DEBT_SLOT);
        expectStorageZero(LEGACY_ORDERS_SLOT);
        expectStorageZero(slots.twoWayDebt);
        expectStorageZero(slots.wrapOnlyDebt);
        expectStorageZero(slots.cUsdcEssPrice);
        expectStorageZero(slots.cUsdcEssAmount);
        expectStorageZero(slots.compEssPrice);
        expectStorageZero(slots.compEssAmount);
        expectStorageZero(LEGACY_OWNER_SLOT);
        expectStorageZero(LEGACY_REGISTRY_SLOT);
        expectStorageZero(LEGACY_NOT_ENTERED_SLOT);
        expectStorageZero(LEGACY_PAUSER_SLOT);
        expectStorageZero(LEGACY_PAUSED_SLOT);

        expectStorageAddress(ROOT_OWNER_SLOT, TIMELOCK);
        expectStorageZero(ROOT_PENDING_OWNER_SLOT);
        assertEq(vm.load(RESERVE, ROOT_INITIALIZER_VERSION_SLOT), bytes32(uint256(2)));
        expectStorageZero(ROOT_INITIALIZER_INITIALIZING_SLOT);

        assertEq(dsu.owner(), RESERVE);
        assertEq(IDSULike(ESS).owner(), RESERVE);
        assertEq(Token18.unwrap(reserve.dsu()), DSU);
        assertEq(Token6.unwrap(reserve.fiat()), USDC);
        assertEq(UFixed18.unwrap(reserve.assets()), postReserveUsdc * 1e12);
        assertEq(UFixed18.unwrap(reserve.mintPrice()), 1 ether);
        assertEq(UFixed18.unwrap(reserve.redeemPrice()), 1 ether);
    }

    function assertForwardReserveBehavior(address user) private {
        NoopFiatReserve reserve = NoopFiatReserve(RESERVE);

        (bool borrowSuccess,) = RESERVE.call(abi.encodeWithSignature("borrow(address,uint256)", user, 1));
        assertFalse(borrowSuccess);

        vm.prank(RESERVE);
        usdc.transfer(user, 100e6);
        vm.prank(user);
        usdc.approve(RESERVE, type(uint256).max);
        vm.prank(user);
        dsu.approve(RESERVE, type(uint256).max);

        vm.prank(user);
        reserve.mint(UFixed18.wrap(10 ether));
        assertEq(dsu.balanceOf(user), 10 ether);

        vm.prank(user);
        reserve.redeem(UFixed18.wrap(4 ether));
        assertEq(dsu.balanceOf(user), 6 ether);
        assertEq(usdc.balanceOf(user), 94e6);

        (bool initializeSuccess,) = RESERVE.call(abi.encodeWithSignature("initialize()"));
        assertFalse(initializeSuccess);

        vm.expectRevert(NoopFiatReserve.NotImplementedError.selector);
        reserve.issue(UFixed18.wrap(1 ether));
    }

    function mappingSlot(address account, uint256 slot) private pure returns (bytes32) {
        return keccak256(abi.encode(account, slot));
    }

    function orderSlots(address makerToken, address takerToken) private pure returns (bytes32 priceSlot, bytes32 amountSlot) {
        bytes32 innerSlot = mappingSlot(makerToken, 2);
        priceSlot = keccak256(abi.encode(takerToken, innerSlot));
        amountSlot = bytes32(uint256(priceSlot) + 1);
    }

    function storageUint(bytes32 slot) private view returns (uint256) {
        return uint256(vm.load(RESERVE, slot));
    }

    function expectStorageZero(bytes32 slot) private view {
        assertEq(vm.load(RESERVE, slot), bytes32(0));
    }

    function expectStorageAddress(bytes32 slot, address account) private view {
        assertEq(vm.load(RESERVE, slot), bytes32(uint256(uint160(account))));
    }
}
