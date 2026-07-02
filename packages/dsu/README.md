# Emptyset DSU

DSU Token contracts for the Emptyset protocol.

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

Run the DSU tests:

```sh
$ forge test --offline --match-path 'test/dsu/*.t.sol'
```

Run the full test suite:

```sh
$ forge test --offline
```
