// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { DSU as IDSU } from "@emptyset/dsu/contracts/DSU.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { Initializable } from "@equilibria/root/attribute/Initializable.sol";
import { IReserve } from "../interfaces/IReserve.sol";

contract ReserveBase is IReserve, Initializable {
    Token18 public immutable DSU; // solhint-disable-line var-name-mixedcase
    Token6 public immutable USDC; // solhint-disable-line var-name-mixedcase
    ICompoundV3USDC public immutable COMPOUND; // solhint-disable-line var-name-mixedcase

    constructor(Token18 dsu_, Token6 usdc_, ICompoundV3USDC compound_) {
        DSU = dsu_;
        USDC = usdc_;
        COMPOUND = compound_;
    }

    function initialize() external initializer(1) {
        IDSU dsu_ = IDSU(Token18.unwrap(DSU));
        if (dsu_.owner() != address(this)) dsu_.acceptOwnership();
    }

    function mintPrice() public pure returns (UFixed18) {
        return UFixed18Lib.ONE;
    }

    function redeemPrice() public view returns (UFixed18) {
        UFixed18 totalSupply = UFixed18.wrap(IDSU(Token18.unwrap(DSU)).totalSupply()); // TODO: move to root
        return _assets().div(totalSupply).min(UFixed18Lib.ONE);
    }

    function mint(UFixed18 amount) external returns (UFixed18 mintAmount) {
        _pull(amount);
        _deposit(amount);
        mintAmount = _mint(amount);
        _push(mintAmount);
    }

    function redeem(UFixed18 amount) external returns (UFixed18 redemptionAmount) {
        _pull(amount);
        redemptionAmount = _redeem(amount);
        _withdraw(redemptionAmount);
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

    function _pull(UFixed18 amount) internal {
        USDC.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    function _push(UFixed18 amount) internal {
        USDC.push(msg.sender, UFixed6Lib.from(amount));
    }

    function _collateral() internal view returns (UFixed18) {
        return UFixed18Lib.from(COMPOUND.balanceOf(address(this)));
    }

    function _assets() internal view returns (UFixed18) {
        return UFixed18Lib.from(COMPOUND.balanceOf(address(this)));
    }

    function _deposit(UFixed18 amount) internal {
        COMPOUND.supply(USDC, UFixed6Lib.from(amount, true));
    }

    function _withdraw(UFixed18 amount) internal {
        COMPOUND.withdraw(USDC, UFixed6Lib.from(amount));
    }
}

interface ICompoundV3USDC {
    function supply(Token6 asset, UFixed6 amount) external;
    function withdraw(Token6 asset, UFixed6 amount) external;
    function balanceOf(address account) external view returns (UFixed6);
}