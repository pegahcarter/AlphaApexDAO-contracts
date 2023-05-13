// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/IDividendTracker.sol";
import "./interfaces/IWETH.sol";

contract DividendTracker is Ownable, IERC20, IDividendTracker {
    using SafeERC20 for IERC20;

    /* ============ State ============ */

    string private constant _name = "Apex_DividendTracker";
    string private constant _symbol = "Apex_DividendTracker";
    uint256 private constant minTokenBalanceForDividends = 10000 * (10**18);
    uint256 private constant magnitude = 2**128;

    address public immutable weth;
    address public immutable apex;
    IRouter public immutable router;

    uint256 public totalDividendsDistributed;
    uint256 public totalDividendsWithdrawn;

    mapping(address => bool) public excludedFromDividends;

    uint256 private magnifiedDividendPerShare;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => int256) private magnifiedDividendCorrections;
    mapping(address => uint256) private withdrawnDividends;
    mapping(address => uint256) private lastClaimTimes;

    constructor(
        address _weth,
        address _apex,
        address _router
    ) {
        require(_weth != address(0), "WETH address zero");
        require(_apex != address(0), "APEX address zero");
        require(_router != address(0), "Router address zero");

        weth = _weth;
        apex = _apex;
        router = IRouter(_router);
    }

    /* ============ External Functions ============ */

    function distributeDividends(uint256 wethDividends) external {
        require(_totalSupply > 0, "dividends unavailable yet");
        if (wethDividends > 0) {
            IERC20(weth).safeTransferFrom(
                msg.sender,
                address(this),
                wethDividends
            );
            magnifiedDividendPerShare =
                magnifiedDividendPerShare +
                ((wethDividends * magnitude) / _totalSupply);
            emit DividendsDistributed(msg.sender, wethDividends);
            totalDividendsDistributed += wethDividends;
        }
    }

    /* ============ External Owner Functions ============ */

    function setBalance(address account, uint256 newBalance)
        external
        onlyOwner
    {
        if (excludedFromDividends[account]) {
            return;
        }
        if (newBalance >= minTokenBalanceForDividends) {
            _setBalance(account, newBalance);
        } else {
            _setBalance(account, 0);
        }
    }

    function excludeFromDividends(address account, bool excluded)
        external
        onlyOwner
    {
        require(
            excludedFromDividends[account] != excluded,
            "Apex_DividendTracker: account already set to requested state"
        );
        excludedFromDividends[account] = excluded;
        if (excluded) {
            _setBalance(account, 0);
        } else {
            uint256 newBalance = IERC20(apex).balanceOf(account);
            if (newBalance >= minTokenBalanceForDividends) {
                _setBalance(account, newBalance);
            } else {
                _setBalance(account, 0);
            }
        }
        emit ExcludeFromDividends(account, excluded);
    }

    function processAccount(address account) external onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);
        if (amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount);
            return true;
        }
        return false;
    }

    function compoundAccount(address account)
        external
        onlyOwner
        returns (bool)
    {
        (uint256 amount, uint256 tokens) = _compoundDividendOfUser(account);
        if (amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Compound(account, amount, tokens);
            return true;
        }
        return false;
    }

    /* ============ External View Functions ============ */

    function isExcludedFromDividends(address account)
        external
        view
        returns (bool)
    {
        return excludedFromDividends[account];
    }

    function withdrawableDividendOf(address account)
        public
        view
        returns (uint256)
    {
        return accumulativeDividendOf(account) - withdrawnDividends[account];
    }

    function withdrawnDividendOf(address account)
        public
        view
        returns (uint256)
    {
        return withdrawnDividends[account];
    }

    function accumulativeDividendOf(address account)
        public
        view
        returns (uint256)
    {
        int256 a = int256(magnifiedDividendPerShare * balanceOf(account));
        int256 b = magnifiedDividendCorrections[account]; // this is an explicit int256 (signed)
        return uint256(a + b) / magnitude;
    }

    function getAccountInfo(address account)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 withdrawableDividends = withdrawableDividendOf(account);
        uint256 totalDividends = accumulativeDividendOf(account);
        uint256 lastClaimTime = lastClaimTimes[account];
        uint256 withdrawn = withdrawnDividendOf(account);
        return (
            account,
            withdrawableDividends,
            totalDividends,
            lastClaimTime,
            withdrawn
        );
    }

    function getLastClaimTime(address account) external view returns (uint256) {
        return lastClaimTimes[account];
    }

    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply()
        public
        view
        override(IDividendTracker, IERC20)
        returns (uint256)
    {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("Apex_DividendTracker: method not implemented");
    }

    function allowance(address, address)
        public
        pure
        override
        returns (uint256)
    {
        revert("Apex_DividendTracker: method not implemented");
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert("Apex_DividendTracker: method not implemented");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("Apex_DividendTracker: method not implemented");
    }

    /* ============ Internal/Private Functions ============ */

    function _setBalance(address account, uint256 newBalance) internal {
        uint256 currentBalance = _balances[account];
        if (newBalance > currentBalance) {
            uint256 addAmount = newBalance - currentBalance;
            _mint(account, addAmount);
        } else if (newBalance < currentBalance) {
            uint256 subAmount = currentBalance - newBalance;
            _burn(account, subAmount);
        }
    }

    function _mint(address account, uint256 amount) private {
        require(
            account != address(0),
            "Apex_DividendTracker: mint to the zero address"
        );
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
        magnifiedDividendCorrections[account] =
            magnifiedDividendCorrections[account] -
            int256(magnifiedDividendPerShare * amount);
    }

    function _burn(address account, uint256 amount) private {
        require(
            account != address(0),
            "Apex_DividendTracker: burn from the zero address"
        );
        uint256 accountBalance = _balances[account];
        require(
            accountBalance >= amount,
            "Apex_DividendTracker: burn amount exceeds balance"
        );
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        magnifiedDividendCorrections[account] =
            magnifiedDividendCorrections[account] +
            int256(magnifiedDividendPerShare * amount);
    }

    function _withdrawDividendOfUser(address account)
        private
        returns (uint256)
    {
        uint256 _withdrawableDividend = withdrawableDividendOf(account);
        if (_withdrawableDividend > 0) {
            withdrawnDividends[account] += _withdrawableDividend;
            totalDividendsWithdrawn += _withdrawableDividend;
            emit DividendWithdrawn(account, _withdrawableDividend);

            // Convert weth to eth and transfer to account
            IWETH(weth).withdraw(_withdrawableDividend);
            // safe transfer eth
            (bool success, ) = account.call{value: _withdrawableDividend}(new bytes(0));
            require(success, "Safe ETH transfer failed");

            return _withdrawableDividend;
        }
        return 0;
    }

    function _compoundDividendOfUser(address account)
        private
        returns (uint256, uint256)
    {
        uint256 _withdrawableDividend = withdrawableDividendOf(account);
        if (_withdrawableDividend > 0) {
            withdrawnDividends[account] += _withdrawableDividend;
            totalDividendsWithdrawn += _withdrawableDividend;
            emit DividendWithdrawn(account, _withdrawableDividend);

            IRouter.route[] memory routes = new IRouter.route[](1);
            routes[0] = IRouter.route(weth, apex, false);

            bool success = false;
            uint256 tokens = 0;

            uint256 initTokenBal = IERC20(apex).balanceOf(account);
            IERC20(weth).approve(
                address(router),
                _withdrawableDividend
            );
            try
                router
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        _withdrawableDividend,
                        0,
                        routes,
                        address(account),
                        block.timestamp
                    )
            {
                success = true;
                tokens = IERC20(apex).balanceOf(account) - initTokenBal;
            } catch Error(
                string memory /*err*/
            ) {
                success = false;
            }

            if (!success) {
                withdrawnDividends[account] -= _withdrawableDividend;
                totalDividendsWithdrawn -= _withdrawableDividend;
                return (0, 0);
            }

            return (_withdrawableDividend, tokens);
        }
        return (0, 0);
    }
}
