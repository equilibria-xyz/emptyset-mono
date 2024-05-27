// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ReserveBase } from "../ReserveBase.sol";

contract CompoundV3USDCReserve is ReserveBase {
    Token6 public immutable USDC; // solhint-disable-line var-name-mixedcase

    constructor(Token18 dsu_, Token6 usdc_) ReserveBase(dsu_) {
        USDC = usdc_;
    }

    function _pull(UFixed18 amount) internal override {
        USDC.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    function _push(UFixed18 amount) internal override {
        USDC.push(msg.sender, UFixed6Lib.from(amount));
    }

    function _collateral() internal override view returns (UFixed18) {
        return UFixed18Lib.from(USDC.balanceOf(address(this)));
    }

    function _assets() internal override view returns (UFixed18) {
        return UFixed18Lib.from(USDC.balanceOf(address(this)));
    }

    function _deposit(UFixed18) internal pure override {
        return;
    }

    function _withdraw(UFixed18) internal pure override {
        return;
    }
}
