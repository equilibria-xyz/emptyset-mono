// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { CompoundV3USDCReserve, ICompoundV3USDC } from "./CompoundV3USDCReserve.sol";
import { PartialAllocation } from "../attribute/PartialAllocation.sol";

contract PartialCompoundV3USDCReserve is CompoundV3USDCReserve, PartialAllocation {
    constructor(Token18 dsu_, Token6 usdc_, ICompoundV3USDC compound_) CompoundV3USDCReserve(dsu_, usdc_, compound_) { }

    function initialize() public override initializer(2) {
        super.initialize();
        __PartialAllocation__initialize();
    }

    function _allocate(UFixed18 amount) internal override {
        (UFixed18 collateral, UFixed18 assets) = (_collateral(), _assets());
        UFixed18 target = assets.add(collateral).sub(amount).mul(allocation);

        if (collateral.gt(target))
            COMPOUND.withdraw(USDC, UFixed6Lib.from(collateral.sub(target)));
        if (target.gt(collateral))
            COMPOUND.supply(USDC, UFixed6Lib.from(target.sub(collateral)));
    }
}