//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

contract Registry {
    event GreetingUpdated(string newGreeting);

    string public greeting;

    function updateGreeting(string memory newGreeting) external {
        greeting = newGreeting;
        emit GreetingUpdated(newGreeting);
    }
}
