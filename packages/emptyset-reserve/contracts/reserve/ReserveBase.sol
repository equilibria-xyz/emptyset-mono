// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { DSU as IDSU } from "@emptyset/dsu/contracts/DSU.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { Ownable } from "@equilibria/root/attribute/Ownable.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IReserveBase } from "../interfaces/IReserveBase.sol";

/// @title ReserveBase
/// @notice The base contract for all reserves. The underyling strategy is implemented by extending this contract.
abstract contract ReserveBase is IReserveBase, Ownable {
    /// @inheritdoc IReserve
    Token18 public immutable dsu;

    /// @inheritdoc IReserveBase
    address public coordinator;

    /// @inheritdoc IReserveBase
    UFixed18 public allocation;

    /// @notice Construct a new ReserveBase
    /// @param dsu_ The DSU stablecoin that the reserve has authority to issue
    constructor(Token18 dsu_) {
        dsu = dsu_;
    }

    /// @notice Initializes the new ReserveBase
    function __ReserveBase__initialize() internal onlyInitializer {
        // if owner is unset, initialize Ownable
        if (owner() == address(0)) __Ownable__initialize();

        // if the DSU is not owned by the reserve, accept ownership
        if (IDSU(Token18.unwrap(dsu)).owner() != address(this)) IDSU(Token18.unwrap(dsu)).acceptOwnership();
    }

    /// @inheritdoc IReserveBase
    function updateCoordinator(address newCoordinator) external onlyOwner {
        coordinator = newCoordinator;
        emit CoordinatorUpdated(newCoordinator);
    }

    /// @inheritdoc IReserveBase
    function updateAllocation(UFixed18 newAllocation) external onlyCoordinator {
        if (newAllocation.gt(UFixed18Lib.ONE)) revert ReserveBaseInvalidAllocationError();

        allocation = newAllocation;
        emit AllocationUpdated(newAllocation);
    }

    /// @inheritdoc IReserve
    function assets() public view returns (UFixed18) {
        return _unallocated().add(_allocated());
    }

    /// @inheritdoc IReserve
    function mintPrice() public pure returns (UFixed18) {
        // always mint at 1:1
        return UFixed18Lib.ONE;
    }

    /// @inheritdoc IReserve
    function redeemPrice() public view returns (UFixed18) {
        // if overcollateralized, cap at 1:1 redemption / if undercollateralized, redeem pro-rata
        return assets().unsafeDiv(dsu.totalSupply()).min(UFixed18Lib.ONE);
    }

    /// @inheritdoc IReserve
    function mint(UFixed18 amount) external returns (UFixed18 mintAmount) {
        _pull(amount);
        _allocate(UFixed18Lib.ZERO);
        mintAmount = _mint(amount);
        dsu.push(msg.sender, mintAmount);
    }

    /// @inheritdoc IReserve
    function redeem(UFixed18 amount) external returns (UFixed18 redemptionAmount) {
        dsu.pull(msg.sender, amount);
        redemptionAmount = _redeem(amount);
        _allocate(redemptionAmount);
        _push(redemptionAmount);
    }

    /// @inheritdoc IReserve
    function issue(UFixed18 amount) external onlyOwner {
        _issue(amount);
        dsu.push(msg.sender, amount);

        if (redeemPrice().lt(UFixed18Lib.ONE)) revert ReserveBaseInsufficientAssetsError();
    }

    /// @notice Mints new DSU by wrapping the underlying asset
    /// @dev Internal helper function
    /// @param amount The quantity of the underlying assets to wrap
    /// @return mintAmount The quantity of DSU minted
    function _mint(UFixed18 amount) internal returns (UFixed18 mintAmount) {
        mintAmount = amount.mul(mintPrice());

        IDSU(Token18.unwrap(dsu)).mint(UFixed18.unwrap(amount));
        emit Mint(msg.sender, mintAmount, amount);
    }

    /// @notice Redeems underlying assets by burning DSU
    /// @dev Internal helper function
    /// @param amount The quantity of DSU to burn
    /// @return redemptionAmount The quantity of underlying assets redeemed
    function _redeem(UFixed18 amount) internal returns (UFixed18 redemptionAmount) {
        redemptionAmount = amount.mul(redeemPrice());

        IDSU(Token18.unwrap(dsu)).burn(UFixed18.unwrap(amount));
        emit Redeem(msg.sender, amount, redemptionAmount);
    }

    /// @notice Issues new DSU
    /// @dev Internal helper function
    /// @param amount The quantity of DSU to issue
    function _issue(UFixed18 amount) internal {
        IDSU(Token18.unwrap(dsu)).mint(UFixed18.unwrap(amount));
        emit Issue(msg.sender, amount);
    }

    /// @notice Computes the reserve's target allocation in the underlying strategy after removing `amount` assets
    /// @param amount The quantity of assets to remove from the reserve
    /// @return allocated The quantity of assets allocated to the underlying strategy
    /// @return target The target quantity of assets to allocate to the underlying strategy
    function _compute(UFixed18 amount) private view returns (UFixed18 allocated, UFixed18 target) {
        UFixed18 unallocated = _unallocated();
        allocated = _allocated();
        target = unallocated.add(allocated).sub(amount).mul(allocation);
    }

    /// @notice Updates the reserve's allocation in the underlying strategy from `allocated` to `target`
    /// @param amount The quantity of assets to remove from the reserve
    function _allocate(UFixed18 amount) private {
        (UFixed18 allocated, UFixed18 target) = _compute(amount);
        _update(allocated, target);
    }

    /// @notice Returns the quantity of assets allocated to the reserve's underylying strategy (ex. USD-value of cUSDC)
    /// @return The quantity of assets allocated to the reserve's underylying strategy
    function _unallocated() internal virtual view returns (UFixed18);

    /// @dev Returns the quantity of assets unallocated in the reserve (ex. USDC)
    /// @return The quantity of assets unallocated in the reserve
    function _allocated() internal virtual view returns (UFixed18);

    /// @notice Pulls underlying assets from the caller
    /// @param amount The quantity of underlying assets to pull (scaled to 18 decimal places)
    function _pull(UFixed18 amount) internal virtual;

    /// @dev Pushes underlying assets to the caller
    /// @param amount The quantity of underlying assets to push (scaled to 18 decimal places)
    function _push(UFixed18 amount) internal virtual;

    /// @notice Updates the reserve's allocation in the underlying strategy from `collateral` to `target`
    /// @param allocated The quantity of assets allocated to the underlying strategy
    /// @param target The target quantity of assets to allocate to the underlying strategy
    function _update(UFixed18 allocated, UFixed18 target) internal virtual;

    /// @dev Only the coordinator can call the function
    modifier onlyCoordinator {
        if (msg.sender != coordinator) revert ReserveBaseNotCoordinatorError();

        _;
    }
}
