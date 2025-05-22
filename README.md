# DeFi Stablecoin Protocol

## Intro

This project is implements a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.
The main Contract is called DSCEngine.sol and it severves as the execution protocol of this project. Included is the DecentralizedStableCoin, which is a burnable ERC20 Token.

This system is designed as a minimal system and features the Token maintaining a peg of 1 Token == 1 US$
 
  This stablecoin has the properties:
  - Exogenous collateral
  - US Dollar pegging
  - Stabilization Algorithm

This system should always be over collateralized. At no point should the value of all collateral <= US$ backed value of all DSC

## Summary

1. Relative Stability: Anchored (or Pegged) -> $1.00
    1. Chainlink Price feed.
    2. Function to exchange ETH & BTC -> $$$
2. Stability Mechanism (Minting): Algorithmic (Decentralized)
    1. People can only mint the stablecoin with enough collateral (coded)
3. Collateral: Exogenous (Crypto)
    1. wETH
    2. wBTC

## Techstack
- Solidity (Programming Language)
- [Foundry](https://book.getfoundry.sh/) (Smart Contract Development Tool)
- [Chainlink-Pricefeeds](https://docs.chain.link/data-feeds/price-feeds) (Price Oracle)
- [Openzeppelin](https://www.openzeppelin.com/contracts) (Smart Contract Library)

## Foundry Documentation

https://book.getfoundry.sh/

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

Run local tests on Sepolia by forking
```shell
$ forge test --fork-url $SEPOLIA_RPC_URL
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil
Anvil is Foundrys local dev blockchain
```shell
$ anvil
```

### Deploy

1. Setup environment variables
Set your SEPOLIA_RPC_URL and PRIVATE_KEY as environment variables. You can add them to a .env file, similar to what you see in .env.example.

 - PRIVATE_KEY: The private key of your account (like from metamask). NOTE: FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
 - SEPOLIA_RPC_URL: This is url of the sepolia testnet node you're working with. You can get setup with one for free from Alchemy. Optionally, add your ETHERSCAN_API_KEY if you want to verify your contract on Etherscan.

2. Get testnet ETH
Head over to faucets.chain.link and get some testnet ETH. You should see the ETH show up in your metamask.

3. Deploy

```shell
$ forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```