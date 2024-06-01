// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ReserveBase } from "../ReserveBase.sol";

contract NoopUSDCReserve is ReserveBase {
    Token6 public immutable usdc;

    constructor(Token18 dsu_, Token6 usdc_) ReserveBase(dsu_) {
        usdc = usdc_;
    }

    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();
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

    function _allocated() internal override pure returns (UFixed18) {
        return UFixed18Lib.ZERO;
    }

    function _update(UFixed18, UFixed18) internal pure override {
        return;
    }
}
