// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ReserveBase } from "../ReserveBase.sol";

/// @title NoopFiatReserve
/// @notice A reserve with the following configuration:
///         - Its underlying asset is a 6-decimal fiat token (ex. USDC, USDT)
///         - Its strategy does not deploy the underlying asset
contract NoopFiatReserve is ReserveBase {
    /// @dev The fiat token
    Token6 public immutable fiat;

    /// @notice Constructs a new NoopFiatReserve
    /// @param dsu_ The DSU token
    /// @param fiat_ The fiat token
    constructor(Token18 dsu_, Token6 fiat_) ReserveBase(dsu_) {
        fiat = fiat_;
    }

    /// @notice Initializes the new NoopFiatReserve
    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();
    }

    /// @inheritdoc ReserveBase
    function _pull(UFixed18 amount) internal override {
        fiat.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    /// @inheritdoc ReserveBase
    function _push(UFixed18 amount) internal override {
        fiat.push(msg.sender, UFixed6Lib.from(amount));
    }

    /// @inheritdoc ReserveBase
    function _unallocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(fiat.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _allocated() internal override pure returns (UFixed18) {
        return UFixed18Lib.ZERO;
    }

    /// @inheritdoc ReserveBase
    function _update(UFixed18, UFixed18) internal pure override {
        return;
    }
}
