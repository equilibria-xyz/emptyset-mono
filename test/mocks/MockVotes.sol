// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

contract MockVotes {
    uint96 private immutable _votes;

    constructor(uint256 votes_) {
        _votes = uint96(votes_);
    }

    function getPriorVotes(address, uint256) external view returns (uint96) {
        return _votes;
    }
}
