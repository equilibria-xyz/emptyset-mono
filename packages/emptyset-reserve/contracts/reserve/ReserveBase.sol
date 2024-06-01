// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { DSU as IDSU } from "@emptyset/dsu/contracts/DSU.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { Initializable } from "@equilibria/root/attribute/Initializable.sol";
import { IReserve } from "../interfaces/IReserve.sol";

// TODO: natspec
// TODO: aave impl
// TODO: owner hook to withdraw excess

abstract contract ReserveBase is IReserve, Initializable {
    Token18 public immutable DSU; // solhint-disable-line var-name-mixedcase

    constructor(Token18 dsu_) {
        DSU = dsu_;
    }

    function __ReserveBase__initialize() internal onlyInitializer {
        IDSU dsu_ = IDSU(Token18.unwrap(DSU));
        if (dsu_.owner() != address(this)) dsu_.acceptOwnership();
    }

    function mintPrice() public pure returns (UFixed18) {
        return UFixed18Lib.ONE;
    }

    function redeemPrice() public view returns (UFixed18) {
        UFixed18 totalSupply = UFixed18.wrap(IDSU(Token18.unwrap(DSU)).totalSupply()); // TODO: move to root
        return _assets().add(_collateral()).div(totalSupply).min(UFixed18Lib.ONE);
    }

    function mint(UFixed18 amount) external returns (UFixed18 mintAmount) {
        _pull(amount); // TODO: these pulls / push don't differentiate?
        _allocate(UFixed18Lib.ZERO);
        mintAmount = _mint(amount);
        _push(mintAmount);
    }

    function redeem(UFixed18 amount) external returns (UFixed18 redemptionAmount) {
        _pull(amount); // TODO: these pulls / push don't differentiate?
        redemptionAmount = _redeem(amount);
        _allocate(redemptionAmount);
        _push(redemptionAmount);
    }

    function _mint(UFixed18 amount) internal returns (UFixed18 mintAmount) {
        mintAmount = amount.mul(mintPrice());

        IDSU(Token18.unwrap(DSU)).mint(UFixed18.unwrap(amount));
        emit Mint(msg.sender, mintAmount, amount);
    }

    function _redeem(UFixed18 amount) internal returns (UFixed18 redemptionAmount) {
        redemptionAmount = amount.mul(redeemPrice());

        IDSU(Token18.unwrap(DSU)).burn(UFixed18.unwrap(amount));
        emit Redeem(msg.sender, amount, redemptionAmount);
    }

    /// @dev Quantity of assets unallocated in the reserve (ex. USDC)
    function _assets() internal virtual view returns (UFixed18);

    /// @dev Quantity of assets allocated to the reserve's underylying strategy (ex. USD-value of cUSDC)
    function _collateral() internal virtual view returns (UFixed18);

    /// @dev Pull assets from the caller
    function _pull(UFixed18 amount) internal virtual;

    /// @dev Push assets to the caller
    function _push(UFixed18 amount) internal virtual;

    /// @dev Perform allocation in the underlying strategy, setting aside `amount` assets for withdrawal
    function _allocate(UFixed18 amount) internal virtual;
}
