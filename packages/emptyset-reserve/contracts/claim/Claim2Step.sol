// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.35;

import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGovToken is IERC20 {
    function delegate(address delegatee) external;
    function delegates(address account) external view returns (address);
}

contract Delegatable is Ownable {
    Token18 public immutable token;

    constructor(Token18 token_, address delegate_) {
        token = token_;
        _g().delegate(delegate_);
    }

    function close() external onlyOwner {
        token.push(_g().delegates(address(this)), token.balanceOf());
    }

    function _g() private view returns (IGovToken) {
        return IGovToken(Token18.unwrap(token));
    }
}

contract Claim2Step is Ownable2Step {
    error ClosedError();
    error OpenedError();
    error NotInitializedError();
    error NotImplementedError();

    event Locked(address indexed account, UFixed18 amount, UFixed6 reward);
    event Unlocked(address indexed account, UFixed18 amount, UFixed6 reward);

    Token6 public immutable fiat;
    Token18 public immutable token;
    uint256 public immutable deadline;

    UFixed18 public totalLocked;
    mapping(address => UFixed18) public lockedOf;
    mapping(address => Delegatable) public delegates;

    constructor(address owner_, Token6 fiat_, Token18 token_, uint256 deadline_) {
        fiat = fiat_;
        token = token_;
        deadline = deadline_;
        super.transferOwnership(owner_);
    }

    function transferOwnership(address) public pure override {
        revert NotImplementedError();
    }

    function renounceOwnership() public pure override {
        revert NotImplementedError();
    }

    function lock(UFixed18 amount) external {
        if (!initialized()) revert NotInitializedError();
        if (closed()) revert ClosedError();

        Delegatable delegate = _deployOrGet(msg.sender);
        UFixed18 unlockedSupply = token.totalSupply().sub(totalLocked);
        UFixed6 reward = UFixed6Lib.from(UFixed18Lib.from(fiat.balanceOf()).muldiv(amount, unlockedSupply));

        totalLocked = totalLocked.add(amount);
        lockedOf[msg.sender] = lockedOf[msg.sender].add(amount);

        token.pullTo(msg.sender, address(delegate), amount);
        fiat.push(msg.sender, reward);

        emit Locked(msg.sender, amount, reward);
    }

    function unlock() external {
        if (!closed()) revert OpenedError();

        UFixed18 amount = lockedOf[msg.sender];
        UFixed6 reward = UFixed6Lib.from(UFixed18Lib.from(fiat.balanceOf()).muldiv(amount, totalLocked));

        totalLocked = totalLocked.sub(amount);
        lockedOf[msg.sender] = lockedOf[msg.sender].sub(amount);

        delegates[msg.sender].close();
        fiat.push(msg.sender, reward);

        emit Unlocked(msg.sender, amount, reward);
    }

    function close() external onlyOwner {
        if (!closed()) revert OpenedError();
        fiat.push(owner());
    }

    function initialized() public view returns (bool) {
        return pendingOwner() == address(0);
    }

    function closed() public view returns (bool) {
        return block.timestamp >= deadline;
    }

    function _deployOrGet(address account) private returns (Delegatable delegate) {
        if (address(delegate = delegates[account]) == address(0)) {
            delegate = new Delegatable(token, account);
            delegates[account] = delegate;
        }
    }
}
