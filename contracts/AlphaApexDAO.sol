// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRouter } from "./interfaces/IRouter.sol";
import { IPairFactory } from "./interfaces/IPairFactory.sol";
import { DividendTracker } from "./DividendTracker.sol";
import { ITokenStorage } from "./interfaces/ITokenStorage.sol";
import { IAlphaApexDAO } from "./interfaces/IAlphaApexDAO.sol";

contract AlphaApexDAO is Ownable, IERC20, IAlphaApexDAO {
    using SafeERC20 for IERC20;

    /* ============ State ============ */

    string private constant _name = "AlphaApexDAO";
    string private constant _symbol = "APEX";

    DividendTracker public immutable dividendTracker;
    IRouter public immutable router;
    IERC20 public immutable weth;
    ITokenStorage public tokenStorage;

    address public multiRewards; // Can trigger dividend distribution.
    address public treasury;
    address public pair;

    uint256 public treasuryFeeBuyBPS = 100;
    uint256 public liquidityFeeBuyBPS = 50;
    uint256 public dividendFeeBuyBPS = 50;

    uint256 public treasuryFeeSellBPS = 600;
    uint256 public liquidityFeeSellBPS = 200;
    uint256 public dividendFeeSellBPS = 400;

    uint256 public totalFeeBuyBPS;
    uint256 public totalFeeSellBPS;

    uint256 public swapTokensAtAmount = 10_000 * (10**18);
    uint256 public lastSwapTime;

    bool public swapAllToken = true;
    bool public compoundingEnabled = true;

    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 private _totalSupply;

    bool private swapping;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFees;

    constructor(
        address _weth,
        address _router,
        address _treasury
    ) {
        require(_weth != address(0), "WETH address zero");
        require(_router != address(0), "Router address zero");
        require(
            _treasury != address(0),
            "Treasury address zero"
        );

        weth = IERC20(_weth);
        treasury = _treasury;

        router = IRouter(_router);

        dividendTracker = new DividendTracker(
            _weth,
            address(this),
            address(router)
        );

        dividendTracker.excludeFromDividends(address(dividendTracker), true);
        dividendTracker.excludeFromDividends(address(this), true);
        dividendTracker.excludeFromDividends(address(router), true);

        excludeFromFees(address(this), true);
        excludeFromFees(address(dividendTracker), true);

        _mint(treasury, 1_000_000_000 * 1e18);
        
        totalFeeBuyBPS = treasuryFeeBuyBPS + liquidityFeeBuyBPS + dividendFeeBuyBPS;
        totalFeeSellBPS = treasuryFeeSellBPS + liquidityFeeSellBPS + dividendFeeSellBPS;
    }

    function initialize() public {
        require(pair == address(0), "Already initialized");
        pair = IPairFactory(router.factory()).createPair(
                address(this),
                address(weth),
                false
            );
        _setAutomatedMarketMakerPair(pair, true);

    }

    /* ============ External View Functions ============ */

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function allowance(address owner, address spender)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        external
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function withdrawableDividendOf(address account)
        external
        view
        returns (uint256)
    {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function isExcludedFromDividends(address account)
        external
        view
        returns (bool)
    {
        return dividendTracker.isExcludedFromDividends(account);
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    /* ============ External Functions ============ */

    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "Apex: decreased allowance < 0"
        );
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }

    function triggerDividendDistribution() external {
        require(msg.sender == multiRewards, "Only callable by MultiRewards");

        uint256 contractTokenBalance = balanceOf(address(tokenStorage));

        uint256 contractWETHBalance = weth.balanceOf(address(tokenStorage));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap && // true
            !swapping // swapping=false !false true
        ) {
            swapping = true;

            if (!swapAllToken) {
                contractTokenBalance = swapTokensAtAmount;
            }
            _executeSwap(contractTokenBalance, contractWETHBalance);

            lastSwapTime = block.timestamp;
            swapping = false;
        }
    }

    function transfer(address recipient, uint256 amount)
        external
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "Apex: tx amount > allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    function claim() external payable {
        bool result = dividendTracker.processAccount(_msgSender());

        require(result, "Apex: claim failed");
    }

    function compound() external {
        require(compoundingEnabled, "Apex: compounding not enabled");
        bool result = dividendTracker.compoundAccount(_msgSender());

        require(result, "Apex: compounding failed");
    }

    /* ============ Internal/Private Functions ============ */

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "Apex: transfer from 0 address");
        require(recipient != address(0), "Apex: transfer to 0 address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Apex: transfer exceeds balance");

        uint256 contractTokenBalance = balanceOf(address(tokenStorage));
        uint256 contractWETHBalance = weth.balanceOf(address(tokenStorage));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap && // true
            !swapping && // swapping=false !false true
            !automatedMarketMakerPairs[sender] && // no swap on remove liquidity step 1 or DEX buy
            sender != address(router) && // no swap on remove liquidity step 2
            sender != owner() &&
            recipient != owner()
        ) {
            swapping = true;

            if (!swapAllToken) {
                contractTokenBalance = swapTokensAtAmount;
            }
            _executeSwap(contractTokenBalance, contractWETHBalance);

            lastSwapTime = block.timestamp;
            swapping = false;
        }

        bool takeFee;
        bool isBuy;

        if (
            sender == address(pair) ||
            recipient == address(pair)
        ) {
            takeFee = true;
            isBuy = sender == address(pair);
        }

        if (_isExcludedFromFees[sender] || _isExcludedFromFees[recipient]) {
            takeFee = false;
        }

        if (swapping ) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 fee = isBuy ? 
                amount * (treasuryFeeBuyBPS + liquidityFeeBuyBPS + dividendFeeBuyBPS) / 10_000 :
                amount * (treasuryFeeSellBPS + liquidityFeeSellBPS + dividendFeeSellBPS) / 10_000;
            amount -= fee;
            _executeTransfer(sender, address(tokenStorage), fee);
            tokenStorage.addFee(isBuy, fee);
        }

        _executeTransfer(sender, recipient, amount);

        dividendTracker.setBalance(sender, balanceOf(sender));
        dividendTracker.setBalance(recipient, balanceOf(recipient));
    }

    function _executeTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Apex: tx amount > balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "Apex: approve from 0 address");
        require(spender != address(0), "Apex: approve to 0 address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address account, uint256 amount) private {
        require(account != address(0), "Apex: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    /// @dev Apply the ratio of buy to sell fees accumulated to each fee rate to
    ///         determine the "actual" fee rate
    function _calcSwapTokens(
        uint256 tokens,
        uint256 buyToSellRatio,
        uint256 sellToBuyRatio,
        uint256 buyFeeBPS,
        uint256 sellFeeBPS
    ) private view returns (uint256 swapTokens) {
        uint256 tokensFeeBuy = tokens * buyToSellRatio * buyFeeBPS / totalFeeBuyBPS / 1e18;
        uint256 tokensFeeSell = tokens * sellToBuyRatio * sellFeeBPS / totalFeeSellBPS / 1e18;
        swapTokens = tokensFeeBuy + tokensFeeSell;
    }

    function _executeSwap(uint256 tokens, uint256 weths) private {
        if (tokens == 0) {
            return;
        }

        uint256 buyToSellRatio = 1e18 * tokenStorage.feesBuy() / 
            (tokenStorage.feesBuy() + tokenStorage.feesSell());
        uint256 sellToBuyRatio = 1e18 - buyToSellRatio;

        uint256 swapTokensTreasury;
        if (treasury != address(0) && treasuryFeeBuyBPS + treasuryFeeSellBPS > 0) {
            swapTokensTreasury = _calcSwapTokens(
                tokens,
                buyToSellRatio,
                sellToBuyRatio,
                treasuryFeeBuyBPS,
                treasuryFeeSellBPS
            );
        }

        uint256 swapTokensDividends;
        if (dividendTracker.totalSupply() > 0 && dividendFeeBuyBPS + dividendFeeSellBPS > 0) {
            swapTokensDividends = _calcSwapTokens(
                tokens,
                buyToSellRatio,
                sellToBuyRatio,
                dividendFeeBuyBPS,
                dividendFeeSellBPS
            );
        }

        uint256 tokensForLiquidity = tokens -
            swapTokensTreasury -
            swapTokensDividends;
        uint256 swapTokensLiquidity = tokensForLiquidity / 2;
        uint256 addTokensLiquidity = tokensForLiquidity - swapTokensLiquidity;
        uint256 swapTokensTotal = swapTokensTreasury +
            swapTokensDividends +
            swapTokensLiquidity;

        uint256 initWETHBal = weth.balanceOf(address(tokenStorage));
        tokenStorage.swapTokensForWETH(swapTokensTotal);
        uint256 wethSwapped = (weth.balanceOf(address(tokenStorage)) -
            initWETHBal) + weths;

        uint256 wethTreasury = (wethSwapped * swapTokensTreasury) /
            swapTokensTotal;
        uint256 wethDividends = (wethSwapped * swapTokensDividends) /
            swapTokensTotal;
        uint256 wethLiquidity = wethSwapped - wethTreasury - wethDividends;

        if (wethTreasury > 0) {
            tokenStorage.transferWETH(treasury, wethTreasury);
        }

        tokenStorage.addLiquidity(addTokensLiquidity, wethLiquidity);
        emit SwapAndAddLiquidity(
            swapTokensLiquidity,
            wethLiquidity,
            addTokensLiquidity
        );

        if (wethDividends > 0) {
            tokenStorage.distributeDividends(swapTokensDividends, wethDividends);
        }
    }

    function _setAutomatedMarketMakerPair(address _pair, bool value) private {
        require(
            automatedMarketMakerPairs[_pair] != value,
            "Apex: AMM pair is same value"
        );
        automatedMarketMakerPairs[_pair] = value;
        if (value) {
            dividendTracker.excludeFromDividends(_pair, true);
        }
        emit SetAutomatedMarketMakerPair(_pair, value);
    }

    /* ============ External Owner Functions ============ */

    function setMultiRewardsAddress(address _multiRewards) external onlyOwner {
        require(_multiRewards != address(0), "Cannot set address zero");
        multiRewards = _multiRewards;
    }

    function setTokenStorage(address _tokenStorage) external onlyOwner {
        require(
            address(tokenStorage) == address(0),
            "Apex: tokenStorage already set"
        );

        tokenStorage = ITokenStorage(_tokenStorage);
        dividendTracker.excludeFromDividends(address(tokenStorage), true);
        excludeFromFees(address(tokenStorage), true);
        emit SetTokenStorage(_tokenStorage);
    }

    function setAutomatedMarketMakerPair(address _pair, bool value)
        external
        onlyOwner
    {
        require(_pair != pair, "Apex: LP can not be removed");
        _setAutomatedMarketMakerPair(_pair, value);
    }

    function setCompoundingEnabled(bool _enabled) external onlyOwner {
        compoundingEnabled = _enabled;

        emit CompoundingEnabled(_enabled);
    }

    function updateDividendSettings(
        uint256 _swapTokensAtAmount,
        bool _swapAllToken
    ) external onlyOwner {
        swapTokensAtAmount = _swapTokensAtAmount;
        swapAllToken = _swapAllToken;

        emit UpdateDividendSettings(
            _swapTokensAtAmount,
            _swapAllToken
        );
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(
            _isExcludedFromFees[account] != excluded,
            "Apex: same state value"
        );
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function excludeFromDividends(address account, bool excluded)
        external
        onlyOwner
    {
        dividendTracker.excludeFromDividends(account, excluded);
    }

    function rescueToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function rescueETH(uint256 _amount) external onlyOwner {
        payable(msg.sender).transfer(_amount);
    }
}
