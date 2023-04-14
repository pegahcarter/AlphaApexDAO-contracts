// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IAlphaApexDAO } from "./interfaces/IAlphaApexDAO.sol";

contract MultiRewards is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    struct Reward {
        address rewardsDistributor;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }
    IERC20 public stakingToken;
    IERC20 public reflectionToken;
    IAlphaApexDAO private _apex;

    mapping(address => Reward) public rewardData;
    address[] public rewardTokens;

    // user -> reward token -> amount
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    uint256 private _reflectionPerToken;
    mapping(address => uint256) private _userReflectionPerTokenPaid;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        address _stakingToken,
        address _reflectionToken
    ) {
        stakingToken = IERC20(_stakingToken);
        reflectionToken = IERC20(_reflectionToken);
        _apex = IAlphaApexDAO(_stakingToken);
    }

    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) public onlyOwner {
        require(
            rewardData[_rewardsToken].rewardsDuration == 0,
            "Token was already added"
        );
        require(_rewardsDuration > 0, "Reward duration must be non-zero");
        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
    }

    /* ========== VIEWS ========== */

    function rewardTokenLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable(address _rewardsToken)
        public
        view
        returns (uint256)
    {
        return
            Math.min(block.timestamp, rewardData[_rewardsToken].periodFinish);
    }

    function rewardPerToken(address _rewardsToken)
        public
        view
        returns (uint256)
    {
        if (_totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return
            rewardData[_rewardsToken].rewardPerTokenStored +
                (lastTimeRewardApplicable(_rewardsToken) - rewardData[_rewardsToken].lastUpdateTime) *
                rewardData[_rewardsToken].rewardRate * 1e18 / _totalSupply;
    }

    function earned(address account, address _rewardsToken)
        public
        view
        returns (uint256)
    {
        return 
            _balances[account] * (
                rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[account][_rewardsToken]
            ) / 1e18 + rewards[account][_rewardsToken];
    }

    function dividendsEarned(address account) public view returns (uint256) {
        return _balances[account] * (_reflectionPerToken - _userReflectionPerTokenPaid[account]) / 1e32;
    }

    function getRewardForDuration(address _rewardsToken)
        external
        view
        returns (uint256)
    {
        return rewardData[_rewardsToken].rewardRate * rewardData[_rewardsToken].rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function setRewardsDistributor(
        address _rewardsToken,
        address _rewardsDistributor
    ) external onlyOwner {
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
    }

    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[msg.sender][_rewardsToken];
            if (reward > 0) {
                delete rewards[msg.sender][_rewardsToken];
                IERC20(_rewardsToken).safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, _rewardsToken, reward);
            }
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(address _rewardsToken, uint256 reward)
        external
        updateReward(address(0))
    {
        require(rewardData[_rewardsToken].rewardsDistributor == msg.sender);

        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        IERC20(_rewardsToken).safeTransferFrom(
            msg.sender,
            address(this),
            reward
        );

        if (block.timestamp >= rewardData[_rewardsToken].periodFinish) {
            rewardData[_rewardsToken].rewardRate = reward / rewardData[_rewardsToken].rewardsDuration;
        } else {
            uint256 remaining = rewardData[_rewardsToken].periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardData[_rewardsToken].rewardRate;
            rewardData[_rewardsToken].rewardRate = (reward + leftover) / rewardData[_rewardsToken].rewardsDuration;
        }

        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp + rewardData[_rewardsToken].rewardsDuration;
        emit RewardAdded(reward);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != address(stakingToken),
            "Cannot withdraw staking token"
        );
        require(
            rewardData[tokenAddress].lastUpdateTime == 0,
            "Cannot withdraw reward token"
        );
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(address _rewardsToken, uint256 _rewardsDuration)
        external
    {
        require(
            block.timestamp > rewardData[_rewardsToken].periodFinish,
            "Reward period still active"
        );
        require(rewardData[_rewardsToken].rewardsDistributor == msg.sender);
        require(_rewardsDuration > 0, "Reward duration must be non-zero");
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(
            _rewardsToken,
            rewardData[_rewardsToken].rewardsDuration
        );
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = rewardData[token]
                    .rewardPerTokenStored;
            }
        }
        if (account != address(0) && _totalSupply > 0) {
            _processReflectionReward(account);
        }
        _;
    }

    /* ========== PRIVATE ========== */

    /**
     * Process reflection rewards before each `stake()`, `withdraw()`, `getReward()`.
     */
    function _processReflectionReward(address account) private {
        // Trigger dividend distribution
        _apex.triggerDividendDistribution();
        // We trust Apex implementation that `withdrawableDividendOf()`
        // is equal to amount checked in `processAccount()` in DividendTracker.sol.
        // which is called by `claim()` in AlphaApexDAO.sol
        uint256 reflection = _apex.withdrawableDividendOf(address(this));
        if (reflection > 0) {
            _apex.claim();
            _reflectionPerToken = reflection * 1e32 / _totalSupply +  _reflectionPerToken;
        }
        uint256 reward = dividendsEarned(account);
        _userReflectionPerTokenPaid[account] = _reflectionPerToken;
        if (reward > 0) {
            reflectionToken.safeTransfer(account, reward);
            emit ReflectionPaid(account, reward);
        }
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(
        address indexed user,
        address indexed rewardsToken,
        uint256 reward
    );
    event ReflectionPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(address token, uint256 newDuration);
    event Recovered(address token, uint256 amount);
}
