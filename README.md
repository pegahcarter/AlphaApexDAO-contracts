# <h1 align="center"> Alpha Apex DAO </h1>

## TODO
* [ ] DAI => USDC
    * [x] rename vars
    * [ ] set contract addresses
    * [ ] token rounding check
* [x] Add logic for buy orders
* [x] Add logic for sell orders
* [ ] Setup
    * [ ] Configure initial distribution recipients and amounts 
    * [ ] Determine `minTokenBalanceForDividends`
    * [ ] Determine `swapTokensAtAmount`
    * [ ] Should fee rates be configurable?
* [ ] Validate Dividends/MultiRewards logic does not round from USDC decimals

* [ ] Safemath
    * [x] Rmv from MultiRewards
    * [ ] Re-validate math 
* [x] Rmv max wallet checks
* [ ] Deployment script
    * [ ] Test deployment script
* [ ] Tests
    * [ ] Deployment checks
    * [ ] Buy logic
    * [ ] Sell logic
    * [ ] transfer logic
* [x] Fix imports

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for instructions on how to install and use Foundry.
