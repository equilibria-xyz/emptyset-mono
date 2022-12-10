//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./Registry.sol";

contract Greeter {
    event Greet(string greeting);

    Registry public registry;

    constructor(Registry registry_) {
        registry = registry_;
    }

    function greet() public returns (string memory greeting) {
        greeting = registry.greeting();
        emit Greet(greeting);
    }
}
