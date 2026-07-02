# Emptyset Reserve

Reserve contracts for the Emptyset protocol.

## Usage

### Pre Requisites

Install Foundry and initialize submodules from the repository root:

```sh
$ git submodule update --init --recursive
```

### Compile

Compile the smart contracts:

```sh
$ forge build
```

### Test

Run the reserve tests:

```sh
$ forge test --offline --match-path 'test/reserve/*.t.sol'
```

Run the full test suite:

```sh
$ forge test --offline
```

Run the mainnet fork migration test with `MAINNET_NODE_URL` set:

```sh
$ forge test --offline --match-path test/reserve/L1Migrator.mainnet.t.sol
```
