// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/uniswap/IUniswapRouterV2.sol";
import "../interfaces/badger/IController.sol";
import "../interfaces/badger/ISettV4h.sol";
import "../interfaces/solidex/ILpDepositor.sol";
import "../interfaces/solidly/IBaseV1Router01.sol";

import {route} from "../interfaces/solidly/IBaseV1Router01.sol";
import {BaseStrategy} from "../deps/BaseStrategy.sol";

contract StrategySolidexOxdUsdc is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // Solidex
    ILpDepositor public constant lpDepositor =
        ILpDepositor(0x26E1A0d851CF28E697870e1b7F053B605C8b060F);

    // Solidly
    address public constant baseV1Router01 = 0xa38cd27185a464914D3046f0AB9d43356B34829D;

    // Spookyswap
    address public constant uniswapV02Router = 0xF491e7B69E4244ad4002BC14e878a34207E38c29; // Spookyswap

    // ===== Token Registry =====

    IERC20Upgradeable public constant oxd =
        IERC20Upgradeable(0xc165d941481e68696f43EE6E99BFB2B23E0E3114);
    IERC20Upgradeable public constant usdc =
        IERC20Upgradeable(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    IERC20Upgradeable public constant solid =
        IERC20Upgradeable(0x888EF71766ca594DED1F0FA3AE64eD2941740A20);
    IERC20Upgradeable public constant sex =
        IERC20Upgradeable(0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7);
    IERC20Upgradeable public constant wftm =
        IERC20Upgradeable(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    // Constants
    uint256 public constant MAX_BPS = 10000;

    // slippage tolerance 0.5% (divide by MAX_BPS) - Changeable by Governance or Strategist
    uint256 public sl;

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );
    event PerformanceFeeGovernance(
        address indexed destination,
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );
    event PerformanceFeeStrategist(
        address indexed destination,
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address _want,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );
        /// @dev Add config here
        want = _want;

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        // Set default slippage value
        sl = 50;

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(address(lpDepositor), type(uint256).max);
        solid.safeApprove(uniswapV02Router, type(uint256).max);
        wftm.safeApprove(uniswapV02Router, type(uint256).max);
        sex.safeApprove(baseV1Router01, type(uint256).max);
        oxd.safeApprove(baseV1Router01, type(uint256).max);
        usdc.safeApprove(baseV1Router01, type(uint256).max);
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "StrategySolidexOxdUsdc";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        return lpDepositor.userBalances(
            address(this),
            want
        );
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return false;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](5);
        protectedTokens[0] = want; // OXD/USDC LP
        protectedTokens[1] = address(sex); // SEX
        protectedTokens[2] = address(solid); // SOLID
        protectedTokens[3] = address(oxd); // OXD
        protectedTokens[4] = address(usdc); // USDC
        return protectedTokens;
    }

    /// @notice sets slippage tolerance for liquidity provision
    function setSlippageTolerance(uint256 _s) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        sl = _s;
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        lpDepositor.deposit(want, _amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        lpDepositor.withdraw(want, balanceOfPool());
    }

    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        lpDepositor.withdraw(want, _amount);
        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // 1. Claim rewards
        address[] memory pools = new address[](1);
        pools[0] = want;
        lpDepositor.getReward(pools);

        // 2. Swap all SOLID for wFTM on Spookyswap
        uint256 solidBalance = solid.balanceOf(address(this));
        if (solidBalance > 0) {
            address[] memory path = new address[](2);
            path[0] = address(solid);
            path[1] = address(wftm);
            _swapExactTokensForTokens_spooky(
                uniswapV02Router,
                solidBalance,
                path
            );
        }

        // 3. Swap all SEX for wFTM on Solidly
        uint256 sexBalance = sex.balanceOf(address(this));
        if (sexBalance > 0) {
            _swapExactTokensForTokens_solidly(
                baseV1Router01,
                sexBalance,
                route(address(sex), address(wftm), false) // False to use the volatile route
            );
        }

        // 4. Swap all wFTM for USDC on Spookyswap
        uint256 wftmBalance = wftm.balanceOf(address(this));
        if (wftmBalance > 0) {
            address[] memory path = new address[](2);
            path[0] = address(wftm);
            path[1] = address(usdc);
            _swapExactTokensForTokens_spooky(
                uniswapV02Router,
                wftmBalance,
                path
            );

            // 5. Swap half USDC for OXD on Solidly
            uint256 _half = usdc.balanceOf(address(this)).mul(5000).div(MAX_BPS);
            _swapExactTokensForTokens_solidly(
                baseV1Router01,
                _half,
                route(address(usdc), address(oxd), false) // False to use the volatile route
            );

            // 6. Provide liquidity for OXD/USDC LP Pair
            uint256 _oxdIn = oxd.balanceOf(address(this));
            uint256 _usdcIn = usdc.balanceOf(address(this));
            IBaseV1Router01(baseV1Router01).addLiquidity(
                address(oxd),
                address(usdc),
                false, // Volatile
                _oxdIn,
                _usdcIn,
                _oxdIn.mul(sl).div(MAX_BPS),
                _usdcIn.mul(sl).div(MAX_BPS),
                address(this),
                now
            );
        }

        // 7. Compound WANT
        uint256 earned =
            IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        /// Process fees
        _processRewardsFees(earned, want);

        uint256 earnedAfterFees =
            IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        _deposit(earnedAfterFees);

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earnedAfterFees, block.number);

        /// @dev Harvest must return the amount of want increased
        return earnedAfterFees;
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
    {
        if (performanceFeeGovernance > 0) {
            uint256 governanceRewardsFee = _processFee(
                _token,
                _amount,
                performanceFeeGovernance,
                IController(controller).rewards()
            );

            emit PerformanceFeeGovernance(
                IController(controller).rewards(),
                _token,
                governanceRewardsFee,
                block.number,
                block.timestamp
            );
        }

        if (performanceFeeStrategist > 0) {
            uint256 strategistRewardsFee = _processFee(
                _token,
                _amount,
                performanceFeeStrategist,
                strategist
            );

            emit PerformanceFeeStrategist(
                strategist,
                _token,
                strategistRewardsFee,
                block.number,
                block.timestamp
            );
        }
    }

    function _swapExactTokensForTokens_solidly(
        address router,
        uint256 amountIn,
        route memory routes
    ) internal {
        route[] memory _route = new route[](1);
        _route[0] = routes;
        IBaseV1Router01(router).swapExactTokensForTokens(
            amountIn,
            0,
            _route,
            address(this),
            now
        );
    }

    function _swapExactTokensForTokens_spooky(
        address router,
        uint256 balance,
        address[] memory path
    ) internal {
        IUniswapRouterV2(router).swapExactTokensForTokens(
            balance,
            0,
            path,
            address(this),
            now
        );
    }
}
