// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { StorageSlot } from "@openzeppelin/contracts/utils/StorageSlot.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICERC20 is IERC20 {
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface IManaged is IERC20 {
    function burn(uint256 amount) external;
}

contract L1Migrator {
    struct Decimal {
        uint256 value;
    }

    struct Order {
        Decimal price;
        uint256 amount;
    }

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ICERC20 private constant CUSDC = ICERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    IManaged private constant DSU = IManaged(0x605D26FBd5be761089281d5cec2Ce86eeA667109);
    IManaged private constant ESS = IManaged(0x24aE124c4CC33D6791F8E8B63520ed7107ac8b3e);

    address private constant PROXY_ROOT = 0x4d2A5E3b7831156f62C8dF47604E321cdAF35fec;
    address private constant TIMELOCK = 0x1bba92F379375387bf8F927058da14D47464cB7A;
    address private constant COMP_ADDRESS = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address private constant TWO_WAY_BATCHER = 0xAEf566ca7E84d1E736f999765a804687f39D9094;
    address private constant WRAP_ONLY_BATCHER = 0x0B663CeaCEF01f2f88EB7451C70Aa069f19dB997;

    bytes32 private constant LEGACY_OWNER_SLOT = keccak256("emptyset.v2.implementation.owner");
    bytes32 private constant LEGACY_REGISTRY_SLOT = keccak256("emptyset.v2.implementation.registry");
    bytes32 private constant LEGACY_NOT_ENTERED_SLOT = keccak256("emptyset.v2.implementation.notEntered");
    bytes32 private constant LEGACY_PAUSER_SLOT = keccak256("emptyset.v2.implementation.pauser");
    bytes32 private constant LEGACY_PAUSED_SLOT = keccak256("emptyset.v2.implementation.paused");
    bytes32 private constant ROOT_OWNER_SLOT = keccak256("equilibria.root.Ownable.owner");
    bytes32 private constant ROOT_PENDING_OWNER_SLOT = keccak256("equilibria.root.Ownable.pendingOwner");
    bytes32 private constant ROOT_INITIALIZER_VERSION_SLOT = keccak256("equilibria.root.Initializable.version");
    bytes32 private constant ROOT_INITIALIZER_INITIALIZING_SLOT = keccak256("equilibria.root.Initializable.initializing");

    error NotProxyRootError();
    error InvariantError();

    uint256 totalDebt;
    mapping(address => uint256) debt;
    mapping(address => mapping(address => Order)) orders;

    function initialize() external {
        if (msg.sender != PROXY_ROOT) revert NotProxyRootError();

        _closeCompound();
        _closeBatchers();
        _clearOrders();
        _burnTokens();
        _migrateStorage();

        _invariant();
    }

    function _closeCompound() private {
        CUSDC.redeem(CUSDC.balanceOf(address(this)));
    }

    function _closeBatchers() private {
        // recall balance
        DSU.transferFrom(TWO_WAY_BATCHER, address(this), DSU.balanceOf(TWO_WAY_BATCHER));
        USDC.transferFrom(TWO_WAY_BATCHER, address(this), USDC.balanceOf(TWO_WAY_BATCHER));

        // clear debt
        totalDebt = 0;
        delete debt[TWO_WAY_BATCHER];
        delete debt[WRAP_ONLY_BATCHER];
    }

    function _clearOrders() private {
        delete orders[address(CUSDC)][address(ESS)];
        delete orders[COMP_ADDRESS][address(ESS)];
    }

    function _burnTokens() private {
        DSU.burn(DSU.balanceOf(address(this)));
        ESS.burn(ESS.balanceOf(address(this)));
    }

    function _migrateStorage() private {
        // migrate owner
        StorageSlot.getAddressSlot(LEGACY_OWNER_SLOT).value = address(0);
        StorageSlot.getAddressSlot(ROOT_OWNER_SLOT).value = TIMELOCK;
        StorageSlot.getAddressSlot(ROOT_PENDING_OWNER_SLOT).value = address(0);

        // clear registry
        StorageSlot.getAddressSlot(LEGACY_REGISTRY_SLOT).value = address(0);

        // clear reentrancy guard
        StorageSlot.getBooleanSlot(LEGACY_NOT_ENTERED_SLOT).value = false;

        // clear pausable
        StorageSlot.getAddressSlot(LEGACY_PAUSER_SLOT).value = address(0);
        StorageSlot.getBooleanSlot(LEGACY_PAUSED_SLOT).value = false;

        // set initializer
        StorageSlot.getUint256Slot(ROOT_INITIALIZER_VERSION_SLOT).value = 2;
        StorageSlot.getBooleanSlot(ROOT_INITIALIZER_INITIALIZING_SLOT).value = false;
    }

    function _invariant() private view {
        if (DSU.totalSupply() > USDC.balanceOf(address(this)) * 1e12) revert InvariantError();
    }
}
