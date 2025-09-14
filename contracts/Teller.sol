// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Teller
 * @notice This contract facilitates the buying and selling of SatCoin for supported stablecoins.
 * @dev It uses a tiered dynamic slippage model based on the trade size (in BTC equivalent)
 * and fetches the base price from Chainlink price feeds.
 * All percentage calculations are done using basis points (1% = 100 bps).
 */
contract Teller is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    // --- Constants ---

    /// @notice The maximum allowed trade size, equivalent to 100 BTC.
    uint256 public constant MAX_TRADE_BTC_EQUIVALENT = 100 * 1e8 * 1e18;

    /// @notice The precision for SatCoin, which is pegged to BTC sats. 1 SatCoin = 10^-8 BTC.
    /// @dev 1 BTC = 10^8 sats. 1 SatCoin (18 decimals) = 1 sat.
    /// So, 1 BTC (in wei) = 1e18 BTC wei = 1e8 sats (in wei) = 1e8 * 1e18 SatCoin wei.
    uint256 public constant BTC_TO_SATOSHI = 1e8;

    /// @notice Basis points denominator (100%). 1% = 100 bps.
    uint256 public constant BASIS_POINTS = 10000;

    // --- State Variables ---

    /// @notice The SatCoin token contract address.
    IERC20 public satCoin;

    /// @notice The price feed contract address (for BTC <> any stablecoin)
    AggregatorV3Interface public priceFeed;

    /// @notice The price feed decimals, fetch from priceFeed.decimals()
    uint8 public priceFeedDecimals;

    /// @notice The coefficient for the slippage formula (k). 10000 represents 1.0.
    uint256 public slippageCoefficient;
    
    /// @notice Mapping from stablecoin address to its decimals offset.
    mapping(address => uint8) public stablecoinDecimals;


    // --- Events ---

    event SupportedTokenAdded(address indexed token, uint8 decimals);
    event SupportedTokenRemoved(address indexed token);
    event SlippageCoefficientSet(uint256 newCoefficient);
    // event Trade(
    //     address indexed user,
    //     address indexed tokenIn,
    //     address indexed tokenOut,
    //     uint256 amountIn,
    //     uint256 amountOut
    // );
    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    // --- Constructor ---

    /**
     * @notice Deploys the Teller contract.
     * @param _satCoinAddress The address of the SatCoin ERC20 token.
     * @param _priceFeedAddress The address of the Chainlink price feed for BTC/USD.
     * @param _initialOwner The initial owner of the contract.
     */
    function initialize(
        address _satCoinAddress,
        address _priceFeedAddress,
        address _initialOwner
    ) public initializer {
        require(
            _satCoinAddress != address(0),
            "Teller: Invalid SatCoin address"
        );

        __Ownable_init(_initialOwner);
        __Ownable2Step_init();

        satCoin = IERC20(_satCoinAddress);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        priceFeedDecimals = priceFeed.decimals();
        slippageCoefficient = 10000; // Default k = 1.0
    }

    // --- Admin Functions ---

    /**
     * @notice Adds a supported stablecoin.
     * @param tokenAddress The address of the stablecoin ERC20 token.
     * @param decimals The decimals of the stablecoin.
     */
    function addSupportedToken(
        address tokenAddress,
        uint8 decimals
    ) public onlyOwner {
        require(tokenAddress != address(0), "Teller: Invalid token address");
        require(stablecoinDecimals[tokenAddress] == 0, "Teller: Token already supported");
        require(decimals > 0, "Teller: Invalid decimals");

        stablecoinDecimals[tokenAddress] = decimals;
        emit SupportedTokenAdded(tokenAddress, decimals);
    }

    function removeSupportedToken(
        address tokenAddress
    ) public onlyOwner {
        require(stablecoinDecimals[tokenAddress] > 0, "Teller: Token not supported");
        stablecoinDecimals[tokenAddress] = 0;

        emit SupportedTokenRemoved(tokenAddress);
    }

    /**
     * @notice Sets the slippage coefficient 'k' for the dynamic slippage formula.
     * @param newCoefficient The new coefficient. 10000 represents 1.0.
     */
    function setSlippageCoefficient(
        uint256 newCoefficient
    ) public onlyOwner {
        require(newCoefficient > 0, "Teller: Coefficient must be positive");
        slippageCoefficient = newCoefficient;
        emit SlippageCoefficientSet(newCoefficient);
    }

    /**
     * @notice Deposits Satcoin or Stablecoins into this contract.
     * @dev Used for liquidity management.
     * @param tokenAddress The address of the token to deposit.
     * @param amount The amount to deposit.
     */
    function deposit(
        address tokenAddress,
        uint256 amount
    ) public {
        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(_msgSender(), address(this), amount);
        emit Deposited(tokenAddress, _msgSender(), amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from this contract to the owner's address.
     * @dev Used for liquidity management.
     * @param tokenAddress The address of the token to withdraw.
     * @param amount The amount to withdraw.
     */
    function withdraw(
        address tokenAddress,
        uint256 amount
    ) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(amount <= balance, "Teller: Insufficient balance");
        token.safeTransfer(_msgSender(), amount);
        emit Withdrawn(tokenAddress, _msgSender(), amount);
    }

}
