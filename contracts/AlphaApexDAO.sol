// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import { DividendTracker} from "./DividendTracker.sol";
import { ITokenStorage} from "./interfaces/ITokenStorage.sol";
import { IAlphaApexDAO} from "./interfaces/IAlphaApexDAO.sol";

contract AlphaApexDAO is Ownable, IERC20, IAlphaApexDAO {
    using SafeERC20 for IERC20;

    /* ============ State ============ */

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    string private constant _name = "AlphaApexDAO";
    string private constant _symbol = "APEX";

    DividendTracker public immutable dividendTracker;
    IUniswapV2Router02 public immutable uniswapV2Router;
    IERC20 public immutable usdc;
    ITokenStorage public tokenStorage;

    address public multiRewards; // Can trigger dividend distribution.
    address public marketingWallet;
    address public uniswapV2Pair;

    uint256 public treasuryFeeBPS = 700;
    uint256 public liquidityFeeBPS = 200;
    uint256 public dividendFeeBPS = 300;
    uint256 public totalFeeBPS = 1200;
    uint256 public swapTokensAtAmount = 100000 * (10**18);
    uint256 public lastSwapTime;

    bool public swapAllToken = true;
    bool public swapEnabled = true;
    bool public taxEnabled = true;
    bool public compoundingEnabled = true;

    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 private _totalSupply;

    bool private swapping;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFees;

    constructor(
        address _usdc,
        address _uniswapRouter,
        address _marketingWallet
    ) {
        require(_usdc != address(0), "USDC address zero");
        require(_uniswapRouter != address(0), "Uniswap router address zero");
        require(
            _marketingWallet != address(0),
            "Marketing wallet address zero"
        );

        usdc = IERC20(_usdc);
        marketingWallet = _marketingWallet;

        uniswapV2Router = IUniswapV2Router02(_uniswapRouter);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
                address(this),
                _usdc
            );

        dividendTracker = new DividendTracker(
            _usdc,
            address(this),
            address(uniswapV2Router)
        );

        _setAutomatedMarketMakerPair(uniswapV2Pair, true);

        dividendTracker.excludeFromDividends(address(dividendTracker), true);
        dividendTracker.excludeFromDividends(address(this), true);
        dividendTracker.excludeFromDividends(owner(), true);
        dividendTracker.excludeFromDividends(address(uniswapV2Router), true);
        dividendTracker.excludeFromDividends(address(DEAD), true);

        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(dividendTracker), true);

        _mint(owner(), 1_000_000_000 * 1e18);
    }

    /* ============ External View Functions ============ */

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
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

        uint256 contractUSDCBalance = usdc.balanceOf(address(tokenStorage));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            swapEnabled && // True
            canSwap && // true
            !swapping // swapping=false !false true
        ) {
            swapping = true;

            if (!swapAllToken) {
                contractTokenBalance = swapTokensAtAmount;
            }
            _executeSwap(contractTokenBalance, contractUSDCBalance);

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

    function claim() external {
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
        uint256 contractUSDCBalance = usdc.balanceOf(address(tokenStorage));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            swapEnabled && // True
            canSwap && // true
            !swapping && // swapping=false !false true
            !automatedMarketMakerPairs[sender] && // no swap on remove liquidity step 1 or DEX buy
            sender != address(uniswapV2Router) && // no swap on remove liquidity step 2
            sender != owner() &&
            recipient != owner()
        ) {
            swapping = true;

            if (!swapAllToken) {
                contractTokenBalance = swapTokensAtAmount;
            }
            _executeSwap(contractTokenBalance, contractUSDCBalance);

            lastSwapTime = block.timestamp;
            swapping = false;
        }

        bool takeFee = false;

        if (
            sender == address(uniswapV2Pair) ||
            recipient == address(uniswapV2Pair)
        ) {
            takeFee = true;
        }

        if (_isExcludedFromFees[sender] || _isExcludedFromFees[recipient]) {
            takeFee = false;
        }

        if (swapping || !taxEnabled) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 fees = (amount * totalFeeBPS) / 10000;
            amount -= fees;
            _executeTransfer(sender, address(tokenStorage), fees);
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

    function _executeSwap(uint256 tokens, uint256 usdcs) private {
        if (tokens == 0) {
            return;
        }

        uint256 swapTokensMarketing = 0;
        if (address(marketingWallet) != address(0) && totalFeeBPS > 0) {
            swapTokensMarketing = (tokens * treasuryFeeBPS) / totalFeeBPS;
        }

        uint256 swapTokensDividends = 0;
        if (dividendTracker.totalSupply() > 0 && totalFeeBPS > 0) {
            swapTokensDividends = (tokens * dividendFeeBPS) / totalFeeBPS;
        }

        uint256 tokensForLiquidity = tokens -
            swapTokensMarketing -
            swapTokensDividends;
        uint256 swapTokensLiquidity = tokensForLiquidity / 2;
        uint256 addTokensLiquidity = tokensForLiquidity - swapTokensLiquidity;
        uint256 swapTokensTotal = swapTokensMarketing +
            swapTokensDividends +
            swapTokensLiquidity;

        uint256 initUSDCBal = usdc.balanceOf(address(tokenStorage));
        tokenStorage.swapTokensForUSDC(swapTokensTotal);
        uint256 usdcSwapped = (usdc.balanceOf(address(tokenStorage)) -
            initUSDCBal) + usdcs;

        uint256 usdcMarketing = (usdcSwapped * swapTokensMarketing) /
            swapTokensTotal;
        uint256 usdcDividends = (usdcSwapped * swapTokensDividends) /
            swapTokensTotal;
        uint256 usdcLiquidity = usdcSwapped - usdcMarketing - usdcDividends;

        if (usdcMarketing > 0) {
            tokenStorage.transferUSDC(marketingWallet, usdcMarketing);
        }

        tokenStorage.addLiquidity(addTokensLiquidity, usdcLiquidity);
        emit SwapAndAddLiquidity(
            swapTokensLiquidity,
            usdcLiquidity,
            addTokensLiquidity
        );

        if (usdcDividends > 0) {
            tokenStorage.distributeDividends(swapTokensDividends, usdcDividends);
        }
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "Apex: AMM pair is same value"
        );
        automatedMarketMakerPairs[pair] = value;
        if (value) {
            dividendTracker.excludeFromDividends(pair, true);
        }
        emit SetAutomatedMarketMakerPair(pair, value);
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

    function setWallet(address _marketingWallet, address _liquidityWallet)
        external
        onlyOwner
    {
        require(_marketingWallet != address(0), "Apex: zero!");
        require(_liquidityWallet != address(0), "Apex: zero!");

        marketingWallet = _marketingWallet;
        tokenStorage.setLiquidityWallet(_liquidityWallet);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        external
        onlyOwner
    {
        require(pair != uniswapV2Pair, "Apex: LP can not be removed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function setFee(
        uint256 _treasuryFee,
        uint256 _liquidityFee,
        uint256 _dividendFee
    ) external onlyOwner {
        require(
            _treasuryFee <= 800 && _liquidityFee <= 800 && _dividendFee <= 800,
            "Each fee must be below 8%"
        );

        treasuryFeeBPS = _treasuryFee;
        liquidityFeeBPS = _liquidityFee;
        dividendFeeBPS = _dividendFee;
        totalFeeBPS = _treasuryFee + _liquidityFee + _dividendFee;

        emit SetFee(_treasuryFee, _liquidityFee, _dividendFee);
    }

    function setSwapEnabled(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
        emit SwapEnabled(_enabled);
    }

    function setTaxEnabled(bool _enabled) external onlyOwner {
        taxEnabled = _enabled;
        emit TaxEnabled(_enabled);
    }

    function setCompoundingEnabled(bool _enabled) external onlyOwner {
        compoundingEnabled = _enabled;

        emit CompoundingEnabled(_enabled);
    }

    function updateDividendSettings(
        bool _swapEnabled,
        uint256 _swapTokensAtAmount,
        bool _swapAllToken
    ) external onlyOwner {
        swapEnabled = _swapEnabled;
        swapTokensAtAmount = _swapTokensAtAmount;
        swapAllToken = _swapAllToken;

        emit UpdateDividendSettings(
            _swapEnabled,
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
