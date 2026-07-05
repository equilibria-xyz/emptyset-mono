// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.35;

import { DSU as IDSU } from "@emptyset/dsu/contracts/DSU.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { IReserve } from "../interfaces/IReserve.sol";

/// @title NoopFiatReserve
/// @notice A reserve with the following configuration:
///         - Its underlying asset is a 6-decimal fiat token (ex. USDC, USDT)
///         - Its strategy does not deploy the underlying asset
contract NoopFiatReserve is IReserve {
    /// @dev Not supported by this reserve implementation
    error NotImplementedError();

    /// @inheritdoc IReserve
    Token18 public immutable dsu;

    /// @dev The fiat token
    Token6 public immutable fiat;

    /// @notice Constructs a new NoopFiatReserve
    /// @param dsu_ The DSU token
    /// @param fiat_ The fiat token
    constructor(Token18 dsu_, Token6 fiat_) {
        dsu = dsu_;
        fiat = fiat_;
    }

    /// @inheritdoc IReserve
    function assets() public view returns (UFixed18) {
        return UFixed18Lib.from(fiat.balanceOf());
    }

    /// @inheritdoc IReserve
    function mintPrice() public pure returns (UFixed18) {
        return UFixed18Lib.ONE;
    }

    /// @inheritdoc IReserve
    function redeemPrice() public view returns (UFixed18) {
        return UFixed18Lib.ONE;
    }

    /// @inheritdoc IReserve
    function mint(UFixed18 amount) external returns (UFixed18) {
        fiat.pull(msg.sender, UFixed6Lib.from(amount, true));

        IDSU(Token18.unwrap(dsu)).mint(UFixed18.unwrap(amount));
        dsu.push(msg.sender, amount);

        emit Mint(msg.sender, amount, amount);

        return amount;
    }

    /// @inheritdoc IReserve
    function redeem(UFixed18 amount) external returns (UFixed18) {
        dsu.pull(msg.sender, amount);
        IDSU(Token18.unwrap(dsu)).burn(UFixed18.unwrap(amount));

        fiat.push(msg.sender, UFixed6Lib.from(amount));

        emit Redeem(msg.sender, amount, amount);

        return amount;
    }

    /// @inheritdoc IReserve
    function issue(UFixed18) external pure {
        revert NotImplementedError();
    }
}
