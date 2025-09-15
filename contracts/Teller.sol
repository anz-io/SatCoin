// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "./libraries/MathLib.sol";

using SafeERC20 for IERC20;
using MathLib for uint256;


/**
 * @title Teller
 * @notice This contract facilitates the buying and selling of SatCoin for supported stablecoins.
 * @dev It uses a tiered dynamic slippage model based on the trade size (in BTC equivalent)
 * and fetches the base price from Chainlink price feeds.
 */
contract Teller is Ownable2StepUpgradeable {

    // --- Constants ---

    /// @notice The maximum allowed trade size, equivalent to 100 BTC.
    uint256 public constant MAX_TRADE_SATCOIN_EQUIVALENT = 100 * 1e8 * 1e18;

    /// @notice The precision for SatCoin, which is pegged to BTC sats. 1 SatCoin = 10^-8 BTC.
    /// @dev 1 BTC = 10^8 sats. 1 SatCoin (18 decimals) = 1 sat.
    /// So, 1 BTC (in wei) = 1e18 BTC wei = 1e8 sats (in wei) = 1e8 * 1e18 SatCoin wei.
    uint8 public constant BTC_TO_SATOSHI_DECIMALS = 8;

    /// @notice The price feed decimals, fetch from priceFeed.decimals()
    /// @dev immutable, but assigned in initialize()
    uint8 public PRICE_FEED_DECIMALS;

    /// @notice The SatCoin token contract address.
    /// @dev immutable, but assigned in initialize()
    IERC20 public satCoin;

    /// @notice The price feed contract address (for BTC <> any stablecoin)
    /// @dev immutable, but assigned in initialize()
    AggregatorV3Interface public priceFeed;


    // --- State Variables ---

    /// @notice The coefficient for the slippage. Default to 1e7, representing 
    ///   1 BTC -> 0.1% slippage. This coefficient could be zero.
    uint256 public slippageCoefficient;

    /// @notice The fee rate for the trade in 18 decimals. Default to 0.
    uint256 public feeRate;
    
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
    event FeeRateSet(uint256 oldFeeRate, uint256 newFeeRate);


    // --- Constructor ---

    /**
     * @notice Deploys the Teller contract.
     * @param _initialOwner The initial owner of the contract.
     * @param _satCoinAddress The address of the SatCoin ERC20 token.
     * @param _priceFeedAddress The address of the Chainlink price feed for BTC/USD.
     *         Use https://data.chain.link/feeds/bsc/mainnet/btc-usd
     */
    function initialize(
        address _initialOwner,
        address _satCoinAddress,
        address _priceFeedAddress
    ) public initializer {
        require(_satCoinAddress != address(0), "Teller: Invalid SatCoin address");

        __Ownable_init(_initialOwner);
        __Ownable2Step_init();

        satCoin = IERC20(_satCoinAddress);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        slippageCoefficient = 1e7;  // Represent 1 BTC -> 0.1% slippage
        PRICE_FEED_DECIMALS = priceFeed.decimals();
    }


    // --- Admin Functions ---

    /**
     * @notice Adds a supported stablecoin.
     * @param tokenAddress The address of the stablecoin ERC20 token.
     * @param decimals The decimals of the stablecoin.
     */
    function addSupportedToken(address tokenAddress, uint8 decimals) public onlyOwner {
        require(tokenAddress != address(0), "Teller: Invalid token address");
        require(stablecoinDecimals[tokenAddress] == 0, "Teller: Token already supported");
        require(decimals > 0, "Teller: Invalid decimals");

        stablecoinDecimals[tokenAddress] = decimals;
        emit SupportedTokenAdded(tokenAddress, decimals);
    }

    /**
     * @notice Removes a supported stablecoin.
     * @param tokenAddress The address of the stablecoin ERC20 token.
     */
    function removeSupportedToken(address tokenAddress) public onlyOwner {
        require(stablecoinDecimals[tokenAddress] > 0, "Teller: Token not supported");

        stablecoinDecimals[tokenAddress] = 0;
        emit SupportedTokenRemoved(tokenAddress);
    }

    /**
     * @notice Sets the slippage coefficient 'k' for the dynamic slippage formula.
     * @param newCoefficient The new coefficient. 1e7 represents 1 BTC -> 0.1% slippage.
     */
    function setSlippageCoefficient(uint256 newCoefficient) public onlyOwner {
        slippageCoefficient = newCoefficient;
        emit SlippageCoefficientSet(newCoefficient);
    }

    /**
     * @notice Sets the fee rate for the trade in 18 decimals.
     * @param newFeeRate The new fee rate. Max 1e17 (representing 10%).
     */
    function setFeeRate(uint256 newFeeRate) public onlyOwner {
        require(newFeeRate <= 1e17, "Teller: Invalid fee rate");
        uint256 oldFeeRate = feeRate;
        feeRate = newFeeRate;
        emit FeeRateSet(oldFeeRate, newFeeRate);
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


    // --- View Functions ---

    /**
     * @notice Fetches and normalizes the SatCoin price from the BTC/USD Chainlink feed.
     * @param decimals The decimals of the stablecoin to get the price against.
     * @return The SatCoin price with 18 decimals.
     */
    function getPrice(uint8 decimals) public view returns (uint256) {
        (, int rawPrice, , , ) = priceFeed.latestRoundData();
        require(rawPrice > 0, "Teller: Invalid Chainlink price");

        uint256 price = uint256(rawPrice) * WAD;
        if (decimals > PRICE_FEED_DECIMALS + BTC_TO_SATOSHI_DECIMALS) {
            price *= 10 ** (decimals - PRICE_FEED_DECIMALS - BTC_TO_SATOSHI_DECIMALS);
        } else {
            price /= 10 ** (PRICE_FEED_DECIMALS + BTC_TO_SATOSHI_DECIMALS - decimals);
        }
        return price;
    }

    /**
     * @notice Calculates the slippage on the SatCoin amount.
     * @param satcoinAmount The trade size in SatCoin.
     * @return The slippage in 18 decimals. 1e15 represents 0.1% slippage.
     */
    function calculateSlippage(uint256 satcoinAmount) public view returns (uint256) {
        return satcoinAmount.wMulDown(slippageCoefficient);
    }


    // --- Public User Functions ---

    // /**
    //  * @notice Swaps an exact amount of a supported stablecoin for SatCoin.
    //  * @param tokenIn The address of the stablecoin being paid.
    //  * @param amountIn The amount of stablecoin being paid.
    //  * @param minAmountOut The minimum amount of SatCoin the user is willing to receive.
    //  * @return satCoinAmountOut The amount of SatCoin received.
    //  */
    function buySatCoinExactIn(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256) {
    //     uint256 btcPrice = _getBtcPrice(tokenIn);
    //     uint8 stablecoinDecimals = IERC20Metadata(tokenIn).decimals();

        // 1. Check conditions
        require(stablecoinDecimals[tokenIn] > 0, "Teller: Token not supported");
        require(amountIn > 0, "Teller: Invalid amount");

        // 2. Calculate SatCoin equivalent of the input amount
        uint256 satcoinPrice = getPrice(stablecoinDecimals[tokenIn]);
        uint256 satcoinAmountWithFee = amountIn.wDivDown(satcoinPrice);
        require(
            satcoinAmountWithFee <= MAX_TRADE_SATCOIN_EQUIVALENT, 
            "Teller: Trade size exceeds 100 BTC limit"
        );

        // 3. Calculate SatCoin amount to be received
        uint256 slippage = calculateSlippage(satcoinAmountWithFee);

    //     uint256 satoshiAmount = (btcAmount * BASIS_POINTS) /
    //         (BASIS_POINTS + slippageBps);
    //     uint256 satCoinDecimals = IERC20Metadata(address(satCoin)).decimals();
    //     satCoinAmountOut =
    //         (satoshiAmount * (10 ** satCoinDecimals)) /
    //         BTC_TO_SATOSHI;

    //     require(
    //         satCoinAmountOut >= minAmountOut,
    //         "Teller: Slippage tolerance not met"
    //     );

    //     // 4. Perform token transfers
    //     IERC20(tokenIn).safeTransferFrom(_msgSender(), address(this), amountIn);
    //     satCoin.safeTransfer(_msgSender(), satCoinAmountOut);

    //     emit Trade(
    //         _msgSender(),
    //         tokenIn,
    //         address(satCoin),
    //         amountIn,
    //         satCoinAmountOut
    //     );
    }

    // /**
    //  * @notice Swaps an exact amount of SatCoin for a supported stablecoin.
    //  * @param tokenOut The address of the stablecoin to receive.
    //  * @param amountIn The amount of SatCoin being paid.
    //  * @param minAmountOut The minimum amount of stablecoin the user is willing to receive.
    //  * @return stableCoinAmountOut The amount of stablecoin received.
    //  */
    // function sellSatCoin(
    //     address tokenOut,
    //     uint256 amountIn,
    //     uint256 minAmountOut
    // ) public returns (uint256 stableCoinAmountOut) {
    //     uint256 btcPrice = _getBtcPrice(tokenOut);
    //     uint256 satCoinDecimals = IERC20Metadata(address(satCoin)).decimals();

    //     // 1. Calculate BTC equivalent of the input amount
    //     uint256 satoshiAmount = (amountIn * BTC_TO_SATOSHI) /
    //         (10 ** satCoinDecimals);
    //     uint256 btcAmount = satoshiAmount; // Assuming 1 satoshi = 1 BTC unit at 8 decimals.

    //     require(
    //         btcAmount <= MAX_TRADE_BTC_EQUIVALENT,
    //         "Teller: Trade size exceeds 100 BTC limit"
    //     );

    //     // 2. Calculate slippage
    //     uint256 slippageBps = _calculateSlippage(btcAmount);

    //     // 3. Calculate stablecoin amount to be received
    //     uint8 stablecoinDecimals = IERC20Metadata(tokenOut).decimals();
    //     uint256 baseStableAmount = (satoshiAmount *
    //         btcPrice *
    //         (10 ** (stablecoinDecimals - 8))) /
    //         (10 ** 8);
    //     stableCoinAmountOut =
    //         (baseStableAmount * (BASIS_POINTS - slippageBps)) /
    //         BASIS_POINTS;

    //     require(
    //         stableCoinAmountOut >= minAmountOut,
    //         "Teller: Slippage tolerance not met"
    //     );

    //     // 4. Perform token transfers
    //     satCoin.safeTransferFrom(_msgSender(), address(this), amountIn);
    //     IERC20(tokenOut).safeTransfer(_msgSender(), stableCoinAmountOut);

    //     emit Trade(
    //         _msgSender(),
    //         address(satCoin),
    //         tokenOut,
    //         amountIn,
    //         stableCoinAmountOut
    //     );
    // }

    // // --- Public View Functions ---

    // /**
    //  * @notice Calculates the expected output amount for a SatCoin purchase.
    //  * @param tokenIn The address of the stablecoin being paid.
    //  * @param amountIn The amount of stablecoin being paid.
    //  * @return The expected amount of SatCoin to receive.
    //  */
    // function getAmountOutForBuy(
    //     address tokenIn,
    //     uint256 amountIn
    // ) public view returns (uint256) {
    //     uint256 btcPrice = _getBtcPrice(tokenIn);
    //     uint8 stablecoinDecimals = IERC20Metadata(tokenIn).decimals();
    //     uint256 btcAmount = (amountIn * (10 ** 8)) /
    //         (btcPrice * (10 ** (stablecoinDecimals - 8)));
    //     if (btcAmount > MAX_TRADE_BTC_EQUIVALENT) return 0;

    //     uint256 slippageBps = _calculateSlippage(btcAmount);
    //     uint256 satoshiAmount = (btcAmount * BASIS_POINTS) /
    //         (BASIS_POINTS + slippageBps);
    //     uint256 satCoinDecimals = IERC20Metadata(address(satCoin)).decimals();

    //     return (satoshiAmount * (10 ** satCoinDecimals)) / BTC_TO_SATOSHI;
    // }

    // /**
    //  * @notice Calculates the expected output amount for a SatCoin sale.
    //  * @param tokenOut The address of the stablecoin to receive.
    //  * @param amountIn The amount of SatCoin being paid.
    //  * @return The expected amount of stablecoin to receive.
    //  */
    // function getAmountOutForSell(
    //     address tokenOut,
    //     uint256 amountIn
    // ) public view returns (uint256) {
    //     uint256 btcPrice = _getBtcPrice(tokenOut);
    //     uint256 satCoinDecimals = IERC20Metadata(address(satCoin)).decimals();
    //     uint256 satoshiAmount = (amountIn * BTC_TO_SATOSHI) /
    //         (10 ** satCoinDecimals);
    //     uint256 btcAmount = satoshiAmount;
    //     if (btcAmount > MAX_TRADE_BTC_EQUIVALENT) return 0;

    //     uint256 slippageBps = _calculateSlippage(btcAmount);
    //     uint8 stablecoinDecimals = IERC20Metadata(tokenOut).decimals();
    //     uint256 baseStableAmount = (satoshiAmount *
    //         btcPrice *
    //         (10 ** (stablecoinDecimals - 8))) /
    //         (10 ** 8);

    //     return (baseStableAmount * (BASIS_POINTS - slippageBps)) / BASIS_POINTS;
    // }

}
