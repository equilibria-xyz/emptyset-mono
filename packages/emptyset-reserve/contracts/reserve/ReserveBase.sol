// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { DSU as IDSU } from "@emptyset/dsu/contracts/DSU.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { Ownable } from "@equilibria/root/attribute/Ownable.sol";
import { IReserve } from "../interfaces/IReserve.sol";

// TODO: natspec

abstract contract ReserveBase is IReserve, Ownable {
    error ReserveBaseNotCoordinatorError();
    error ReserveBaseInvalidAllocationError();
    error ReserveBaseInsufficientAssetsError();


    event CoordinatorUpdated(address newCoordinator);
    event AllocationUpdated(UFixed18 newAllocation);

    Token18 public immutable dsu;

    address public coordinator;
    UFixed18 public allocation;

    constructor(Token18 dsu_) {
        dsu = dsu_;
    }

    function __ReserveBase__initialize() internal onlyInitializer {
        if (owner() == address(0)) __Ownable__initialize();
        if (IDSU(Token18.unwrap(dsu)).owner() != address(this)) IDSU(Token18.unwrap(dsu)).acceptOwnership();
    }

    function updateCoordinator(address newCoordinator) external onlyOwner {
        coordinator = newCoordinator;
        emit CoordinatorUpdated(newCoordinator);
    }

    function updateAllocation(UFixed18 newAllocation) external onlyCoordinator {
        if (newAllocation.gt(UFixed18Lib.ONE)) revert ReserveBaseInvalidAllocationError();

        allocation = newAllocation;
        emit AllocationUpdated(newAllocation);
    }

    function assets() public view returns (UFixed18) {
        return _unallocated().add(_allocated());
    }

    function mintPrice() public pure returns (UFixed18) {
        return UFixed18Lib.ONE;
    }

    function redeemPrice() public view returns (UFixed18) {
        UFixed18 totalSupply = UFixed18.wrap(IDSU(Token18.unwrap(dsu)).totalSupply()); // TODO: move to root
        return assets().unsafeDiv(totalSupply).min(UFixed18Lib.ONE);
    }

    function mint(UFixed18 amount) external invariant returns (UFixed18 mintAmount) {
        _pull(amount);
        _allocate(UFixed18Lib.ZERO);
        mintAmount = _mint(amount);
        dsu.push(msg.sender, mintAmount);
    }

    function redeem(UFixed18 amount) external invariant returns (UFixed18 redemptionAmount) {
        dsu.pull(msg.sender, amount);
        redemptionAmount = _redeem(amount);
        _allocate(redemptionAmount);
        _push(redemptionAmount);
    }

    function issue(UFixed18 amount) external invariant onlyOwner {
        _issue(amount);
        dsu.push(msg.sender, amount);
    }

    function _mint(UFixed18 amount) internal returns (UFixed18 mintAmount) {
        mintAmount = amount.mul(mintPrice());

        IDSU(Token18.unwrap(dsu)).mint(UFixed18.unwrap(amount));
        emit Mint(msg.sender, mintAmount, amount);
    }

    function _redeem(UFixed18 amount) internal returns (UFixed18 redemptionAmount) {
        redemptionAmount = amount.mul(redeemPrice());

        IDSU(Token18.unwrap(dsu)).burn(UFixed18.unwrap(amount));
        emit Redeem(msg.sender, amount, redemptionAmount);
    }

    function _issue(UFixed18 amount) internal {
        IDSU(Token18.unwrap(dsu)).mint(UFixed18.unwrap(amount));
        emit Issue(msg.sender, amount);
    }

    function _compute(UFixed18 amount) private view returns (UFixed18 allocated, UFixed18 target) {
        UFixed18 unallocated = _unallocated();
        allocated = _allocated();
        target = unallocated.add(allocated).sub(amount).mul(allocation);
    }

    function _allocate(UFixed18 amount) private {
        (UFixed18 allocated, UFixed18 target) = _compute(amount);
        _update(allocated, target);
    }

    /// @dev Quantity of assets allocated to the reserve's underylying strategy (ex. USD-value of cUSDC)
    function _unallocated() internal virtual view returns (UFixed18);

    /// @dev Quantity of assets unallocated in the reserve (ex. USDC)
    function _allocated() internal virtual view returns (UFixed18);

    /// @dev Pull assets from the caller
    function _pull(UFixed18 amount) internal virtual;

    /// @dev Push assets to the caller
    function _push(UFixed18 amount) internal virtual;

    /// @dev Update the reserve's allocation in the underlying strategy from `collateral` to `target`
    function _update(UFixed18 allocated, UFixed18 target) internal virtual;

    modifier onlyCoordinator {
        if (msg.sender != coordinator) revert ReserveBaseNotCoordinatorError();

        _;
    }

    modifier invariant {
        UFixed18 initialRedeemPrice = redeemPrice();

        _;

        // redeemPrice must not decrease during the state execution
        if (redeemPrice().lt(initialRedeemPrice)) revert ReserveBaseInsufficientAssetsError();
    }
}
