// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { Claim2Step, Delegatable } from "@emptyset/reserve/contracts/claim/Claim2Step.sol";

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
    function proposalThreshold() external view returns (uint256);
    function quorumVotes() external view returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
}

/// @dev Comp/Uni-style governance token surface used by ESS.
interface IEssLike is IERC20 {
    function delegate(address delegatee) external;
    function getCurrentVotes(address account) external view returns (uint256);
}

/// @dev End-to-end: a real GovernorAlpha proposal funds and initializes a freshly deployed Claim2Step, then
///      holders lock/unlock ESS and keep their voting power throughout. Fork-gated on MAINNET_NODE_URL.
contract Claim2StepMainnetTest is Test {
    address private constant TIMELOCK = 0x1bba92F379375387bf8F927058da14D47464cB7A;
    address private constant GOVERNOR = 0x47C61a54B1d24d571F07a79d54543231292f769b;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant ESS = 0x24aE124c4CC33D6791F8E8B63520ed7107ac8b3e;

    uint256 private constant DURATION = 180 days;
    uint256 private constant REWARD = 900_000e6;

    // GovernorAlpha proposal states
    uint8 private constant ACTIVE = 1;
    uint8 private constant SUCCEEDED = 4;
    uint8 private constant QUEUED = 5;
    uint8 private constant EXECUTED = 7;

    IGovernorLike private governor = IGovernorLike(GOVERNOR);
    IEssLike private ess = IEssLike(ESS);
    IERC20 private usdc = IERC20(USDC);

    bool private forkUnavailable;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_NODE_URL", string(""));
        forkUnavailable = bytes(rpc).length == 0;
        if (forkUnavailable) return;

        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK_NUMBER", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);
    }

    function testGovernanceFundsInitializesAndRunsClaim() public {
        vm.skip(forkUnavailable);

        uint256 deadline = block.timestamp + DURATION;
        Claim2Step claim =
            new Claim2Step(TIMELOCK, Token6.wrap(USDC), Token18.wrap(ESS), deadline);

        // the treasury holds the reward that the proposal will route into the claim
        deal(USDC, TIMELOCK, REWARD);

        _passProposal(address(claim));

        // proposal outcome: funded, owned by the timelock, and open for locking
        assertTrue(claim.initialized());
        assertEq(claim.owner(), TIMELOCK);
        assertEq(usdc.balanceOf(address(claim)), REWARD);
        assertEq(Token18.unwrap(claim.token()), ESS);
        assertEq(Token6.unwrap(claim.fiat()), USDC);

        _runClaim(claim, deadline);
    }

    /// @dev Build the two-action proposal, give a proposer voting weight, and drive it to execution.
    function _passProposal(address claim) private {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        string[] memory signatures = new string[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = USDC;
        signatures[0] = "transfer(address,uint256)";
        calldatas[0] = abi.encode(claim, REWARD);

        targets[1] = claim;
        signatures[1] = "acceptOwnership()";
        calldatas[1] = "";

        address proposer = makeAddr("proposer");
        deal(ESS, proposer, governor.quorumVotes() + governor.proposalThreshold() + 1_000e18, true);
        vm.prank(proposer);
        ess.delegate(proposer); // checkpoint the proposer's voting weight
        vm.roll(block.number + 1);

        vm.prank(proposer);
        uint256 id = governor.propose(targets, values, signatures, calldatas, "Claim2Step: fund and initialize");

        (,,, uint256 startBlock, uint256 endBlock,,,,) = governor.proposals(id);
        vm.roll(startBlock + 1);
        assertEq(governor.state(id), ACTIVE);

        vm.prank(proposer);
        governor.castVote(id, true);

        vm.roll(endBlock + 1);
        assertEq(governor.state(id), SUCCEEDED);

        governor.queue(id);
        assertEq(governor.state(id), QUEUED);
        (,, uint256 eta,,,,,,) = governor.proposals(id);
        vm.warp(eta + 1);

        governor.execute(id);
        assertEq(governor.state(id), EXECUTED);
    }

    /// @dev Two holders lock ESS (keeping their votes via the per-user wrapper), govern while locked, then
    ///      sweep the pool on unlock. Each locks a quorum-sized weight so the two of them can carry a proposal.
    function _runClaim(Claim2Step claim, uint256 deadline) private {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 aLock = governor.quorumVotes();
        uint256 bLock = governor.quorumVotes();
        deal(ESS, alice, aLock, true);
        deal(ESS, bob, bLock, true);
        vm.prank(alice);
        ess.approve(address(claim), type(uint256).max);
        vm.prank(bob);
        ess.approve(address(claim), type(uint256).max);

        uint256 supply = ess.totalSupply(); // constant across the lock phase (locks are transfers)

        // --- phase 1: lock ---
        uint256 rewardA = usdc.balanceOf(address(claim)) * aLock / (supply - _totalLocked(claim));
        assertGt(rewardA, 0);
        assertEq(ess.getCurrentVotes(alice), 0);
        vm.prank(alice);
        claim.lock(UFixed18.wrap(aLock));
        assertEq(usdc.balanceOf(alice), rewardA);
        assertEq(ess.balanceOf(alice), 0);
        // custody moved to the wrapper, but alice keeps the voting power
        assertEq(ess.balanceOf(address(claim.delegates(alice))), aLock);
        assertEq(ess.getCurrentVotes(alice), aLock);

        uint256 rewardB = usdc.balanceOf(address(claim)) * bLock / (supply - _totalLocked(claim));
        vm.prank(bob);
        claim.lock(UFixed18.wrap(bLock));
        assertEq(usdc.balanceOf(bob), rewardB);
        assertEq(ess.getCurrentVotes(bob), bLock);

        // --- while locked: the holders govern with their preserved voting power ---
        assertFalse(claim.closed()); // still inside the lock window
        _passLockedHolderProposal(alice, bob, aLock, bLock);

        // --- phase 2: unlock ---
        vm.warp(deadline);
        assertTrue(claim.closed());

        uint256 sweepA = usdc.balanceOf(address(claim)) * aLock / _totalLocked(claim);
        vm.prank(alice);
        claim.unlock();
        assertEq(usdc.balanceOf(alice), rewardA + sweepA);
        assertEq(ess.balanceOf(alice), aLock); // gov returned...
        assertEq(ess.getCurrentVotes(alice), 0); // ...and voting power released with it

        // bob is the last locker, so his unlock sweeps the remainder of the pool
        uint256 sweepB = usdc.balanceOf(address(claim));
        vm.prank(bob);
        claim.unlock();
        assertEq(usdc.balanceOf(bob), rewardB + sweepB);
        assertEq(ess.balanceOf(bob), bLock);
        assertEq(usdc.balanceOf(address(claim)), 0);
    }

    /// @dev A fresh proposal, proposed by locked-holder `alice` and carried to execution by the votes of both
    ///      locked holders — proving locking custody into the claim does not surrender governance power.
    function _passLockedHolderProposal(address alice, address bob, uint256 aLock, uint256 bLock) private {
        GovTarget target = new GovTarget();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(target);
        signatures[0] = "ping()";
        calldatas[0] = "";

        vm.roll(block.number + 1);
        vm.prank(alice); // alice proposes using only her locked (wrapper-delegated) weight
        uint256 id = governor.propose(targets, values, signatures, calldatas, "Locked holders govern");

        (,,, uint256 startBlock, uint256 endBlock,,,,) = governor.proposals(id);
        vm.roll(startBlock + 1);
        assertEq(governor.state(id), ACTIVE);

        vm.prank(alice);
        governor.castVote(id, true);
        vm.prank(bob);
        governor.castVote(id, true);

        // the entire winning tally is locked ESS voting through the wrappers
        (,,,,, uint256 forVotes,,,) = governor.proposals(id);
        assertEq(forVotes, aLock + bLock);
        assertGe(forVotes, governor.quorumVotes());

        vm.roll(endBlock + 1);
        assertEq(governor.state(id), SUCCEEDED);
        governor.queue(id);
        (,, uint256 eta,,,,,,) = governor.proposals(id);
        vm.warp(eta + 1);
        governor.execute(id);
        assertEq(governor.state(id), EXECUTED);

        assertTrue(target.pinged()); // the locked holders' proposal actually executed
    }

    function _totalLocked(Claim2Step claim) private view returns (uint256) {
        return UFixed18.unwrap(claim.totalLocked());
    }
}

/// @dev Trivial governance target so an executed proposal leaves an observable on-chain effect.
contract GovTarget {
    bool public pinged;

    function ping() external {
        pinged = true;
    }
}
