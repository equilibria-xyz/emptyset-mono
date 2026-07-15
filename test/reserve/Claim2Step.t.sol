// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { Claim2Step, Delegatable } from "@emptyset/reserve/contracts/claim/Claim2Step.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockGovToken } from "../mocks/MockGovToken.sol";

contract Claim2StepTest is Test {
    MockERC20 private usdc;
    MockGovToken private gov;
    Claim2Step private claim;

    address private governor = makeAddr("governor");
    address private a = makeAddr("a");
    address private b = makeAddr("b");
    address private c = makeAddr("c");

    uint256 private constant DURATION = 180 days;
    uint256 private constant SUPPLY = 1000e18;
    uint256 private constant REWARD = 900e6;

    uint256 private deadline;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        gov = new MockGovToken("Governance Token", "GOV");

        deadline = block.timestamp + DURATION;
        claim = new Claim2Step(governor, Token6.wrap(address(usdc)), Token18.wrap(address(gov)), deadline);

        gov.mint(a, 500e18);
        gov.mint(b, 300e18);
        gov.mint(c, 200e18);
        assertEq(gov.totalSupply(), SUPPLY);

        vm.prank(a);
        gov.approve(address(claim), type(uint256).max);
        vm.prank(b);
        gov.approve(address(claim), type(uint256).max);
        vm.prank(c);
        gov.approve(address(claim), type(uint256).max);
    }

    /// @dev Funds the pool, mirroring the treasury transferring the reward in before kickoff
    function _fund() private {
        usdc.mint(address(claim), REWARD);
    }

    /// @dev The governor accepts ownership, which opens the lock phase
    function _initialize() private {
        vm.prank(governor);
        claim.acceptOwnership();
    }

    function _wrapperOf(address account) private view returns (address) {
        return address(claim.delegates(account));
    }

    function _locked(address account) private view returns (uint256) {
        return gov.balanceOf(_wrapperOf(account));
    }

    // --- construction & lifecycle ---

    function testConstructor() public {
        assertEq(Token6.unwrap(claim.fiat()), address(usdc));
        assertEq(Token18.unwrap(claim.token()), address(gov));
        assertEq(claim.deadline(), deadline);
        assertEq(claim.owner(), address(this));
        assertEq(claim.pendingOwner(), governor);
        assertFalse(claim.initialized());
        assertFalse(claim.closed());
    }

    function testInitializeViaAcceptOwnership() public {
        _initialize();
        assertEq(claim.owner(), governor);
        assertEq(claim.pendingOwner(), address(0));
        assertTrue(claim.initialized());
    }

    function testLockRevertsBeforeInitialized() public {
        _fund();
        vm.expectRevert(Claim2Step.NotInitializedError.selector);
        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));
    }

    function testTransferOwnershipReverts() public {
        vm.expectRevert(Claim2Step.NotImplementedError.selector);
        claim.transferOwnership(a);
    }

    function testRenounceOwnershipReverts() public {
        vm.expectRevert(Claim2Step.NotImplementedError.selector);
        claim.renounceOwnership();
    }

    function testOnlyPendingOwnerCanInitialize() public {
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        vm.prank(a);
        claim.acceptOwnership();
    }

    function testLockRevertsAfterDeadline() public {
        _fund();
        _initialize();
        vm.warp(deadline);
        vm.expectRevert(Claim2Step.ClosedError.selector);
        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));
    }

    function testUnlockRevertsBeforeDeadline() public {
        _fund();
        _initialize();
        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));

        vm.warp(deadline - 1);
        vm.expectRevert(Claim2Step.OpenedError.selector);
        vm.prank(a);
        claim.unlock();
    }

    // --- core economics ---

    function testLockPaysBaseShareAndPreservesVotes() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));

        // 900e6 * 500 / 1000 = 450e6
        assertEq(usdc.balanceOf(a), 450e6);
        assertEq(usdc.balanceOf(address(claim)), 450e6);

        // gov is custodied in a's wrapper, not a's wallet nor the claim contract
        assertEq(gov.balanceOf(a), 0);
        assertEq(gov.balanceOf(address(claim)), 0);
        assertEq(_locked(a), 500e18);
        assertEq(UFixed18.unwrap(claim.totalLocked()), 500e18);

        // ...but a keeps full governance power over the locked balance
        assertEq(gov.getVotes(a), 500e18);
    }

    function testLockAccumulatesIntoOneWrapper() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(200e18));
        address wrapper = _wrapperOf(a);

        vm.prank(a);
        claim.lock(UFixed18.wrap(300e18));

        // reused the same wrapper; 900*200/1000 + 720*300/800 = 180 + 270 = 450
        assertEq(_wrapperOf(a), wrapper);
        assertEq(usdc.balanceOf(a), 450e6);
        assertEq(_locked(a), 500e18);
        assertEq(gov.getVotes(a), 500e18);
    }

    /// @dev Order-independent: shrinking pool over shrinking unlocked supply gives equal holders equal shares.
    function testEqualHoldersGetEqualShares() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(250e18)); // 900 * 250/1000 = 225
        vm.prank(b);
        claim.lock(UFixed18.wrap(250e18)); // 675 * 250/750 = 225

        assertEq(usdc.balanceOf(a), 225e6);
        assertEq(usdc.balanceOf(b), 225e6);
    }

    /// @dev Full two-phase distribution: c never locks and forfeits its share to a and b, who sweep it in
    ///      phase two pro-rata to their locked amount. Votes are preserved throughout, then returned.
    function testFullDistribution() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18)); // 900 * 500/1000 = 450
        vm.prank(b);
        claim.lock(UFixed18.wrap(300e18)); // 450 * 300/500 = 270

        assertEq(usdc.balanceOf(a), 450e6);
        assertEq(usdc.balanceOf(b), 270e6);
        assertEq(usdc.balanceOf(address(claim)), 180e6);
        assertEq(gov.getVotes(a), 500e18);
        assertEq(gov.getVotes(b), 300e18);

        vm.warp(deadline);

        vm.prank(a);
        claim.unlock(); // 180 * 500/800 = 112.5
        vm.prank(b);
        claim.unlock(); // 67.5 * 300/300 = 67.5

        assertEq(usdc.balanceOf(a), 562_500_000);
        assertEq(usdc.balanceOf(b), 337_500_000);

        // gov fully returned to the holders; votes now follow the returned tokens (self-undelegated)
        assertEq(gov.balanceOf(a), 500e18);
        assertEq(gov.balanceOf(b), 300e18);
        assertEq(gov.getVotes(a), 0);
        assertEq(_locked(a), 0);

        assertEq(usdc.balanceOf(a) + usdc.balanceOf(b), REWARD);
        assertEq(usdc.balanceOf(c), 0);
        assertEq(usdc.balanceOf(address(claim)), 0);
    }

    function testUnclaimedLeftoverStaysStuck() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));
        vm.prank(b);
        claim.lock(UFixed18.wrap(300e18));

        vm.warp(deadline);
        vm.prank(a);
        claim.unlock(); // 180 * 500/800 = 112.5

        assertEq(usdc.balanceOf(a), 562_500_000);
        assertEq(usdc.balanceOf(address(claim)), 67_500_000); // b's un-swept share
        assertEq(_locked(b), 300e18); // b's gov still custodied
    }

    function testDoubleUnlockPaysNothingExtra() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));
        vm.prank(b);
        claim.lock(UFixed18.wrap(300e18));

        vm.warp(deadline);
        vm.prank(a);
        claim.unlock();
        uint256 afterFirst = usdc.balanceOf(a);

        // b remains locked so totalLocked > 0; a's second unlock claims an empty wrapper
        vm.prank(a);
        claim.unlock();
        assertEq(usdc.balanceOf(a), afterFirst);
        assertEq(gov.balanceOf(a), 500e18);
    }

    /// @dev Every payout rounds down and the final claimant sweeps the remainder, so the pool stays solvent.
    function testRoundsDownAndStaysSolvent() public {
        usdc.mint(address(claim), 10e6);
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18)); // 10e6 * 500/1000 = 5e6
        vm.prank(b);
        claim.lock(UFixed18.wrap(300e18)); // 5e6 * 300/500 = 3e6
        vm.prank(c);
        claim.lock(UFixed18.wrap(200e18)); // 2e6 * 200/200 = 2e6

        vm.warp(deadline);
        vm.prank(a);
        claim.unlock();
        vm.prank(b);
        claim.unlock();
        vm.prank(c);
        claim.unlock();

        assertEq(usdc.balanceOf(a) + usdc.balanceOf(b) + usdc.balanceOf(c), 10e6);
        assertEq(usdc.balanceOf(address(claim)), 0);
    }

    // --- manipulation resistance ---

    /// @dev Donating gov directly to the claim contract does not shrink `unlockedSupply` (it is derived from
    ///      internal `totalLocked`, not a live balance), so it cannot inflate a locker's reward.
    function testGovDonationDoesNotInflateReward() public {
        _fund();
        _initialize();

        // c donates its entire holding straight to the claim contract (a transfer, not a mint: supply fixed)
        vm.prank(c);
        gov.transfer(address(claim), 200e18);

        // a still receives exactly its fair base share
        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18));
        assertEq(usdc.balanceOf(a), 450e6);
    }

    /// @dev Live USDC added to the pool simply joins it and is distributed to whoever locks after.
    function testUsdcAddedToPoolIsDistributed() public {
        _fund();
        _initialize();
        usdc.mint(address(claim), 100e6); // pool now 1000e6

        vm.prank(a);
        claim.lock(UFixed18.wrap(500e18)); // 1000e6 * 500/1000 = 500e6
        assertEq(usdc.balanceOf(a), 500e6);
    }

    /// @dev Regression for the wrapper-donation bug: gov sent into a locker's wrapper must not inflate that
    ///      locker's reward nor corrupt `totalLocked` (which would strand other lockers). Accounting is driven
    ///      by the internal `lockedOf` ledger, so the donation is simply gifted back on exit.
    function testWrapperDonationDoesNotInflateOrStrand() public {
        _fund();
        _initialize();

        vm.prank(a);
        claim.lock(UFixed18.wrap(400e18)); // a keeps 100 spare; phase-1 = 900 * 400/1000 = 360
        vm.prank(b);
        claim.lock(UFixed18.wrap(300e18)); // phase-1 = 540 * 300/600 = 270

        // a donates its 100 spare straight into its own wrapper (address is public)
        address wrapperA = _wrapperOf(a);
        vm.prank(a);
        gov.transfer(wrapperA, 100e18);

        vm.warp(deadline);

        vm.prank(a);
        claim.unlock();
        // exactly the fair share (900*400/700), not the inflated 500-based amount, and gov (incl. gift) back
        assertEq(usdc.balanceOf(a), uint256(360e6) + uint256(270e6) * 400 / 700);
        assertEq(gov.balanceOf(a), 500e18);

        // totalLocked fell by the ledgered 400, not the wrapper's 500, so b still exits cleanly
        assertEq(UFixed18.unwrap(claim.totalLocked()), 300e18);
        vm.prank(b);
        claim.unlock();
        assertEq(gov.balanceOf(b), 300e18);
        assertEq(usdc.balanceOf(a) + usdc.balanceOf(b), REWARD);
    }

    /// @dev Unlocking without ever having locked reverts (no wrapper deployed); nothing is at risk.
    function testUnlockWithoutLockReverts() public {
        _fund();
        _initialize();
        vm.warp(deadline);

        vm.expectRevert();
        vm.prank(a);
        claim.unlock();
    }
}
