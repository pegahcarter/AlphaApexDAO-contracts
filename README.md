# <h1 align="center"> Alpha Apex DAO </h1>

## TODO
* [x] DAI => USDC
    * [x] rename vars
    * [x] set contract addresses
* [x] Add logic for buy orders
* [x] Add logic for sell orders
* [x] Setup
    * [x] Configure initial distribution recipients and amounts - all to msig (TODO: address to receive)
    * [x] Determine `minTokenBalanceForDividends`
    * [x] Determine `swapTokensAtAmount`
    * [x] Should fee rates be configurable?
* [x] Validate Dividends/MultiRewards logic does not round from USDC decimals

* [x] Safemath
    * [x] Rmv from MultiRewards
    * [x] Re-validate math 
* [x] Rmv max wallet checks
* [x] Tests
    * [x] Deployment checks
    * [x] Buy logic
    * [x] Sell logic
    * [x] Buy & sell logic
    * [x] transfer logic
* [x] Fix imports

### TODO: for Uniswap v3
* [ ] Conversion from v2 to v3 interface
    * [x] Contract addresses
    * [x] Interface/library imports
    * [x] Create a pool
        * [ ] Test adding liquidity
    * [x] Swap tokens
        * [ ] Test swap
        * [ ] Test calculating swap output
* [ ] Liquidity tokens
    * [x] Send tokens to unique address ("lp") instead of providing liq
        * [ ] Test
    * [x] Function to change lp address
        * [ ] Test

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for instructions on how to install and use Foundry.
