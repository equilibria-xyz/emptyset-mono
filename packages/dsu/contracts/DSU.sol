// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@equilibria/root/control/unstructured/UOwnable.sol";

contract DigitalStandardUnit is ERC20, ERC20Burnable, UOwnable, ERC20Permit {
    constructor()
        ERC20("Digital Standard Unit", "DSU")
        ERC20Permit("Digital Standard Unit")
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
