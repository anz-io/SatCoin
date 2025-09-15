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
    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event FeeRateSet(uint256 oldFeeRate, uint256 newFeeRate);
    event Bought(
        address indexed user,
        address indexed tokenIn,
        uint256 amountInStableCoin,
        uint256 amountOutSatCoin,
        uint256 feeInSatCoin
    );
    event Sold(
        address indexed user,
        address indexed tokenOut,
        uint256 amountInSatCoin,
        uint256 amountOutStableCoin,
        uint256 feeInStableCoin
    );


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

    /**
     * @notice Previews the amount of SatCoin that can be received for an exact amount of `tokenIn`.
     * @param amountIn The amount of the stablecoin being paid.
     * @param tokenIn The address of the stablecoin being paid.
     * @return satCoinAmountOut The expected amount of SatCoin to be received after fees.
     * @return feeAmount The fee charged for the trade, denominated in SatCoin.
     */
    function previewBuyExactIn(
        uint256 amountIn, 
        address tokenIn
    ) public view returns (uint256 satCoinAmountOut, uint256 feeAmount) {
        // 1. Check conditions and calculate the ideal SatCoin output amount.
        require(stablecoinDecimals[tokenIn] > 0, "Teller: Token not supported");
        uint256 price = getPrice(stablecoinDecimals[tokenIn]);
        uint256 idealSatCoinOut = amountIn.wDivDown(price);
        require(idealSatCoinOut <= MAX_TRADE_SATCOIN_EQUIVALENT, "Teller: Trade size exceeds limit");

        // 2. Calculate the amount after applying slippage.
        uint256 slippage = calculateSlippage(idealSatCoinOut);
        uint256 satCoinOutAfterSlippage = idealSatCoinOut.wMulDown(WAD - slippage);

        // 3. Calculate the fee and the final output amount.
        feeAmount = satCoinOutAfterSlippage.wMulDown(feeRate);
        satCoinAmountOut = satCoinOutAfterSlippage - feeAmount;
    }

    /**
     * @notice Previews the amount of stablecoin that received for selling an exact amount of SatCoin.
     * @param amountIn The amount of SatCoin being paid.
     * @param tokenOut The address of the stablecoin to be received.
     * @return stablecoinAmountOut The expected amount of stablecoin to be received after fees.
     * @return feeAmount The fee charged for the trade, denominated in the stablecoin (`tokenOut`).
     */
    function previewSellExactIn(
        uint256 amountIn, 
        address tokenOut
    ) public view returns (uint256 stablecoinAmountOut, uint256 feeAmount) {
        // 1. Check conditions and calculate the ideal stablecoin output amount.
        require(amountIn <= MAX_TRADE_SATCOIN_EQUIVALENT, "Teller: Trade size exceeds limit");
        require(stablecoinDecimals[tokenOut] > 0, "Teller: Token not supported");
        uint256 price = getPrice(stablecoinDecimals[tokenOut]);
        uint256 idealStablecoinOut = amountIn.wMulDown(price);

        // 2. Calculate the amount after applying slippage.
        uint256 slippage = calculateSlippage(amountIn);
        uint256 stablecoinOutAfterSlippage = idealStablecoinOut.wMulDown(WAD - slippage);

        // 3. Calculate the fee and the final output amount.
        feeAmount = stablecoinOutAfterSlippage.wMulDown(feeRate);
        stablecoinAmountOut = stablecoinOutAfterSlippage - feeAmount;
    }

    /**
     * @notice Previews the amount of stablecoin required to receive an exact amount of SatCoin.
     * @param amountOut The exact amount of SatCoin to be received after fees.
     * @param tokenIn The address of the stablecoin to be paid.
     * @return stablecoinAmountIn The expected amount of stablecoin required to be paid.
     * @return feeAmount The fee that will be charged  denominated in SatCoin.
     */
    function previewBuyExactOut(
        uint256 amountOut, 
        address tokenIn
    ) public view returns (uint256 stablecoinAmountIn, uint256 feeAmount) {
        // 1. Reverse calculate the amount before the fee is applied (rounding up).
        require(stablecoinDecimals[tokenIn] > 0, "Teller: Token not supported");
        uint256 satcoinAmountBeforeFee = amountOut.wDivUp(WAD - feeRate);
        feeAmount = satcoinAmountBeforeFee - amountOut;
        require(
            satcoinAmountBeforeFee <= MAX_TRADE_SATCOIN_EQUIVALENT, 
            "Teller: Trade size exceeds limit"
        );

        // 2. Reverse calculate the ideal amount before slippage (rounding up).
        uint256 slippage = calculateSlippage(satcoinAmountBeforeFee);
        uint256 idealSatCoinAmount = satcoinAmountBeforeFee.wDivUp(WAD - slippage);

        // 3. Calculate the final stablecoin input amount (rounding up).
        uint256 price = getPrice(stablecoinDecimals[tokenIn]);
        stablecoinAmountIn = idealSatCoinAmount.wMulUp(price);
    }

    /**
     * @notice Previews the amount of SatCoin required to receive an exact amount of a stablecoin.
     * @param amountOut The exact amount of the stablecoin to be received after fees.
     * @param tokenOut The address of the stablecoin to be received.
     * @return satCoinAmountIn The expected amount of SatCoin required to be paid.
     * @return feeAmount The fee that will be charged denominated in the stablecoin (`tokenOut`).
     */
    function previewSellExactOut(
        uint256 amountOut, 
        address tokenOut
    ) public view returns (uint256 satCoinAmountIn, uint256 feeAmount) {
        // 1. Reverse calculate the amount before the fee is applied (rounding up).
        require(stablecoinDecimals[tokenOut] > 0, "Teller: Token not supported");
        uint256 stablecoinAmountBeforeFee = amountOut.wDivUp(WAD - feeRate);
        feeAmount = stablecoinAmountBeforeFee - amountOut;
        uint256 price = getPrice(stablecoinDecimals[tokenOut]);

        // 2. Estimate the SatCoin input to calculate slippage.
        uint256 estimatedSatCoinIn = stablecoinAmountBeforeFee.wDivUp(price);
        require(
            estimatedSatCoinIn <= MAX_TRADE_SATCOIN_EQUIVALENT, 
            "Teller: Trade size exceeds limit"
        );
        uint256 slippage = calculateSlippage(estimatedSatCoinIn);

        // 3. Reverse calculate the ideal stablecoin amount before slippage (rounding up).
        uint256 idealStablecoinAmount = stablecoinAmountBeforeFee.wDivUp(WAD - slippage);
        satCoinAmountIn = idealStablecoinAmount.wDivUp(price);
    }


    // --- Public User Functions ---

    /**
     * @notice Swaps an exact amount of a supported stablecoin for SatCoin.
     * @param amountIn The exact amount of stablecoin being paid.
     * @param tokenIn The address of the stablecoin being paid.
     * @param minAmountOut The minimum amount of SatCoin the user is willing to receive.
     * @return satCoinAmountOut The amount of SatCoin received after fees.
     * @return feeAmount The fee charged for the trade, denominated in SatCoin.
     */
    function buyExactIn(
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut
    ) public returns (uint256 satCoinAmountOut, uint256 feeAmount) {
        // Preview the output amount
        (satCoinAmountOut, feeAmount) = previewBuyExactIn(amountIn, tokenIn);
        require(satCoinAmountOut >= minAmountOut, "Teller: Insufficient output amount");

        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(_msgSender(), address(this), amountIn);
        satCoin.safeTransfer(_msgSender(), satCoinAmountOut);

        // Event
        emit Bought(_msgSender(), tokenIn, amountIn, satCoinAmountOut, feeAmount);
    }

    /**
     * @notice Swaps an exact amount of SatCoin for a supported stablecoin.
     * @param amountIn The exact amount of SatCoin being paid.
     * @param tokenOut The address of the stablecoin to receive.
     * @param minAmountOut The minimum amount of stablecoin the user is willing to receive.
     * @return stablecoinAmountOut The amount of stablecoin received after fees.
     * @return feeAmount The fee charged for the trade, denominated in the stablecoin.
     */
    function sellExactIn(
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut
    ) public returns (uint256 stablecoinAmountOut, uint256 feeAmount) {
        // Preview the output amount
        (stablecoinAmountOut, feeAmount) = previewSellExactIn(amountIn, tokenOut);
        require(stablecoinAmountOut >= minAmountOut, "Teller: Insufficient output amount");

        // Transfer tokens
        satCoin.safeTransferFrom(_msgSender(), address(this), amountIn);
        IERC20(tokenOut).safeTransfer(_msgSender(), stablecoinAmountOut);

        // Event
        emit Sold(_msgSender(), tokenOut, amountIn, stablecoinAmountOut, feeAmount);
    }

    /**
     * @notice Swaps a variable amount of stablecoin for an exact amount of SatCoin.
     * @param amountOut The exact amount of SatCoin to receive.
     * @param tokenIn The address of the stablecoin being paid.
     * @param maxAmountIn The maximum amount of stablecoin the user is willing to pay.
     * @return stablecoinAmountIn The amount of stablecoin paid.
     * @return feeAmount The fee charged for the trade, denominated in SatCoin.
     */
    function buyExactOut(
        uint256 amountOut,
        address tokenIn,
        uint256 maxAmountIn
    ) public returns (uint256 stablecoinAmountIn, uint256 feeAmount) {
        // Preview the input amount
        (stablecoinAmountIn, feeAmount) = previewBuyExactOut(amountOut, tokenIn);
        require(stablecoinAmountIn <= maxAmountIn, "Teller: Excessive input amount");

        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(_msgSender(), address(this), stablecoinAmountIn);
        satCoin.safeTransfer(_msgSender(), amountOut);

        // Event
        emit Bought(_msgSender(), tokenIn, stablecoinAmountIn, amountOut, feeAmount);
    }

    /**
     * @notice Swaps a variable amount of SatCoin for an exact amount of a supported stablecoin.
     * @param amountOut The exact amount of stablecoin to receive.
     * @param tokenOut The address of the stablecoin to receive.
     * @param maxAmountIn The maximum amount of SatCoin the user is willing to pay.
     * @return satCoinAmountIn The amount of SatCoin paid.
     * @return feeAmount The fee charged for the trade, denominated in the stablecoin.
     */
    function sellExactOut(
        uint256 amountOut,
        address tokenOut,
        uint256 maxAmountIn
    ) public returns (uint256 satCoinAmountIn, uint256 feeAmount) {
        // Preview the input amount
        (satCoinAmountIn, feeAmount) = previewSellExactOut(amountOut, tokenOut);
        require(satCoinAmountIn <= maxAmountIn, "Teller: Excessive input amount");

        // Transfer tokens
        satCoin.safeTransferFrom(_msgSender(), address(this), satCoinAmountIn);
        IERC20(tokenOut).safeTransfer(_msgSender(), amountOut);

        // Event
        emit Sold(_msgSender(), tokenOut, satCoinAmountIn, amountOut, feeAmount);
    }

}
