// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ReserveBase } from "../ReserveBase.sol";

contract CompoundV3USDCReserve is ReserveBase {
    Token6 public immutable usdc;
    ICompoundV3USDC public immutable compound;

    constructor(Token18 dsu_, Token6 usdc_, ICompoundV3USDC compound_) ReserveBase(dsu_) {
        usdc = usdc_;
        compound = compound_;
    }

    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();

        usdc.approve(address(compound));
        // TODO: sanity checks on configuration (is there a market?)
    }

    function _pull(UFixed18 amount) internal override {
        usdc.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    function _push(UFixed18 amount) internal override {
        usdc.push(msg.sender, UFixed6Lib.from(amount));
    }

    function _unallocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(usdc.balanceOf(address(this)));
    }

    function _allocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(compound.balanceOf(address(this)));
    }

    function _update(UFixed18 collateral, UFixed18 target) internal override {
        if (collateral.gt(target))
            compound.withdraw(usdc, UFixed6Lib.from(collateral.sub(target)));
        if (target.gt(collateral))
            compound.supply(usdc, UFixed6Lib.from(target.sub(collateral)));
    }
}

interface ICompoundV3USDC {
    function supply(Token6 asset, UFixed6 amount) external;
    function withdraw(Token6 asset, UFixed6 amount) external;
    function balanceOf(address account) external view returns (UFixed6);
}