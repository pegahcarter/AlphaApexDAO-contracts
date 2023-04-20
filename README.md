# <h1 align="center"> Alpha Apex DAO </h1>

## TODO
* [x] DAI => USDC
    * [x] rename vars
    * [x] set contract addresses
* [x] Add logic for buy orders
* [x] Add logic for sell orders
* [ ] Setup
    * [x] Configure initial distribution recipients and amounts - all to msig (TODO: address to receive)
    * [x] Determine `minTokenBalanceForDividends`
    * [x] Determine `swapTokensAtAmount`
    * [x] Should fee rates be configurable?
* [ ] Validate Dividends/MultiRewards logic does not round from USDC decimals

* [ ] Safemath
    * [x] Rmv from MultiRewards
    * [ ] Re-validate math 
* [x] Rmv max wallet checks
* [ ] Tests
    * [x] Deployment checks
    * [x] Buy logic
    * [ ] Sell logic
    * [ ] Buy & sell logic
    * [x] transfer logic
* [x] Fix imports

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for instructions on how to install and use Foundry.
