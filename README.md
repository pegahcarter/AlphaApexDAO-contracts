# <h1 align="center"> Alpha Apex DAO </h1>

## Getting started
1. Create `.env` file following `.env.example` template
2.
```
forge build
forge test
```
### Deployment
```
source .env

forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url $ARBITRUM_RPC_URL --verify -vvvv
```

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for instructions on how to install and use Foundry.
