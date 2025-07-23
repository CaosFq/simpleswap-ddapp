// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

/**
 * @title SimpleSwap
 * @dev A simplified decentralized exchange (DEX) contract replicating core Uniswap V2 functionalities
 * for a single pair of ERC-20 tokens. This contract allows users to provide liquidity,
 * swap tokens, and retrieve liquidity. It incorporates basic security measures and
 * common AMM (Automated Market Maker) mathematical principles.
 */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SimpleSwap {
    // --- State Variables and Constants ---
    // Enables safe ERC-20 functions like .safeTransferFrom() and .safeTransfer()
    // on IERC20 types, which helps prevent reentrancy and ensures proper return value handling.
    using SafeERC20 for IERC20;

    // Address of the first token in the pair. Tokens are sorted by address in the constructor
    // to ensure a consistent ordering (token0 < token1), which is crucial for
    // cross-contract compatibility and simplifying logic.
    address public immutable token0;
    // Address of the second token in the pair (token1 > token0).
    address public immutable token1;

    // Current reserve balance of token0 held within the pool.
    // These balances determine the current price ratio.
    uint256 public reserve0;
    // Current reserve balance of token1 held within the pool.
    uint256 public reserve1;

    // Total supply of LP (Liquidity Provider) tokens. These tokens represent a share
    // of the total liquidity in the pool.
    uint256 public totalLiquidity;
    // Mapping from liquidity provider address to their balance of LP tokens.
    mapping(address => uint256) public liquidityBalances;

    // Minimum amount of liquidity to mint when the pool is initialized.
    // This prevents "dust attacks" where a tiny amount of initial liquidity
    // could be used to manipulate the pool's ratio heavily for subsequent larger deposits.
    uint256 private constant MINIMUM_LIQUIDITY = 10**3; // Example: 1000 units of LP tokens

    // Numerator for the 0.3% swap fee (997/1000 = 0.997).
    // This means 0.3% of the input tokens are taken as a fee and added to the reserves,
    // benefiting liquidity providers.
    uint256 private constant SWAP_FEE_NUMERATOR = 997;
    // Denominator for the swap fee.
    uint256 private constant SWAP_FEE_DENOMINATOR = 1000;

    // --- Events for transparent off-chain monitoring of pool activity ---
    /**
     * @dev Emitted when liquidity is added to the pool.
     * @param provider The address of the liquidity provider.
     * @param amount0 The amount of token0 added.
     * @param amount1 The amount of token1 added.
     * @param liquidity The amount of LP tokens minted to the provider.
     */
    event AddLiquidity(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @dev Emitted when liquidity is removed from the pool.
     * @param provider The address of the liquidity provider.
     * @param amount0 The amount of token0 removed.
     * @param amount1 The amount of token1 removed.
     * @param liquidity The amount of LP tokens burned by the provider.
     */
    event RemoveLiquidity(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @dev Emitted when a token swap occurs.
     * @param sender The address that initiated the swap.
     * @param amountIn The amount of tokens sent into the pool.
     * @param amountOut The amount of tokens received from the pool.
     * @param tokenIn The address of the token sent into the pool.
     * @param tokenOut The address of the token received from the pool.
     */
    event Swap(address indexed sender, uint256 amountIn, uint256 amountOut, address indexed tokenIn, address indexed tokenOut);

    /**
     * @dev Emitted after the pool's reserve balances are updated.
     * This event is crucial for off-chain monitoring of the pool's state.
     * @param newReserve0 The updated balance of token0.
     * @param newReserve1 The updated balance of token1.
     */
    event UpdateLiquidity(uint256 newReserve0, uint256 newReserve1);

    // --- Constructor: Contract Initialization ---
    /**
     * @dev Initializes the SimpleSwap contract with two ERC-20 token addresses.
     * Tokens are sorted by address to ensure consistency (token0 is always less than token1).
     * @param _tokenA The address of the first ERC-20 token.
     * @param _tokenB The address of the second ERC-20 token.
     */
    constructor(address _tokenA, address _tokenB) {
        // Ensure token addresses are not zero
        require(_tokenA != address(0) && _tokenB != address(0), "SimpleSwap: ZERO_ADDRESS");
        // Ensure token addresses are not identical
        require(_tokenA != _tokenB, "SimpleSwap: IDENTICAL_ADDRESSES");
        // Sort tokens to ensure a consistent ordering (token0 always has the lower address)
        (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }

    // --- Internal Helper Functions (Supporting Logic) ---
    /**
     * @dev Calculates the integer square root of a uint256 number.
     * This is a common and efficient implementation for Solidity, using the Babylonian method.
     * @param y The number to calculate the square root of.
     * @return z The integer square root of y.
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return 0;
        uint256 x = y / 2 + 1; // Initial guess, ensuring x > sqrt(y) if y > 0
        uint256 nextX = (x + y / x) / 2;
        // Iterate until the approximation converges (nextX becomes greater than or equal to x)
        while (nextX < x) {
            x = nextX;
            nextX = (x + y / x) / 2;
        }
        return x; // Returns the integer part of the square root
    }

    /**
     * @dev Updates the contract's reserve balances.
     * This function is crucial for maintaining the liquidity pool's state and is called
     * after any tokens are moved into or out of the contract's reserves (e.g., during add, remove, swap).
     * It also enforces non-zero reserves after the initial liquidity provision.
     * @param newReserve0 The new balance of token0 in the contract.
     * @param newReserve1 The new balance of token1 in the contract.
     */
    function _update(uint256 newReserve0, uint256 newReserve1) internal {
        // If the pool already has liquidity, ensure that the new reserves remain positive.
        // This helps maintain the constant product invariant (x * y = k) by preventing one reserve
        // from going to zero unexpectedly without the other being empty.
        if (reserve0 > 0 || reserve1 > 0) {
            require(newReserve0 > 0 && newReserve1 > 0, "SimpleSwap: ZERO_RESERVES_AFTER_UPDATE");
        }
        
        reserve0 = newReserve0; // Update token0 reserve
        reserve1 = newReserve1; // Update token1 reserve
        emit UpdateLiquidity(newReserve0, newReserve1); // Emit event with updated reserves for off-chain monitoring
    }

    /**
     * @dev Quotes an amount of tokenB for a given amount of tokenA, based on current reserves.
     * This function provides the theoretical exchange rate *without* considering swap fees.
     * It's a pure function, meaning it doesn't read or modify contract state.
     * @param amountA The amount of tokenA to be quoted.
     * @param reserveA The current reserve balance of tokenA in the pool.
     * @param reserveB The current reserve balance of tokenB in the pool.
     * @return amountB The calculated amount of tokenB.
     */
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        // Ensure the input amount is positive.
        require(amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        // Ensure both reserves are positive to avoid division by zero or nonsensical calculations.
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        // Calculate amountB proportionally: amountB = (amountA * reserveB) / reserveA
        amountB = (amountA * reserveB) / reserveA;
    }

    /**
     * @dev Calculates the optimal amounts of token0 and token1 to add to the pool.
     * This ensures that the amounts added are proportional to the current reserves,
     * similar to Uniswap V2's approach, minimizing impermanent loss for the provider.
     * If the pool is empty, it uses the desired amounts directly.
     * @param _amount0Desired Desired amount of token0 from the user.
     * @param _amount1Desired Desired amount of token1 from the user.
     * @param _currentReserve0 Current reserve of token0 in the pool.
     * @param _currentReserve1 Current reserve of token1 in the pool.
     * @return amount0Optimal The actual optimal amount of token0 to use for the deposit.
     * @return amount1Optimal The actual optimal amount of token1 to use for the deposit.
     */
    function _calculateOptimalAmounts(
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _currentReserve0,
        uint256 _currentReserve1
    ) internal pure returns (uint256 amount0Optimal, uint256 amount1Optimal) {
        // For the very first liquidity provision (empty pool), accept desired amounts as optimal.
        if (_currentReserve0 == 0 && _currentReserve1 == 0) {
            amount0Optimal = _amount0Desired;
            amount1Optimal = _amount1Desired;
        } else {
            // Calculate how much token1 is needed for the desired token0 based on current ratio
            uint256 amount1Needed = (_amount0Desired * _currentReserve1) / _currentReserve0;
            // If the user provides enough or more token1 than needed for their desired token0,
            // use the desired token0 and the calculated needed token1.
            if (amount1Needed <= _amount1Desired) {
                amount0Optimal = _amount0Desired;
                amount1Optimal = amount1Needed;
            } else {
                // If the user does not have enough token1, adjust the desired token0 proportionally
                // to match the available token1.
                uint256 amount0Needed = (_amount1Desired * _currentReserve0) / _currentReserve1;
                amount0Optimal = amount0Needed;
                amount1Optimal = _amount1Desired;
            }
        }
    }

    /**
     * @dev Calculates the amount of LP tokens to mint for adding liquidity.
     * This function is pure (does not modify state) and its result is used to update balances.
     * For the initial liquidity, it uses the geometric mean. For subsequent liquidity, it
     * ensures proportionality to existing total liquidity and reserves.
     * @param _amount0 Actual amount of token0 added to the pool.
     * @param _amount1 Actual amount of token1 added to the pool.
     * @param _totalLiquidity Current total supply of LP tokens.
     * @param _reserve0 Current reserve balance of token0.
     * @param _reserve1 Current reserve balance of token1.
     * @return newLiquidity The amount of LP tokens to mint.
     */
    function _calculateLiquidityToMint(
        uint256 _amount0,
        uint256 _amount1,
        uint256 _totalLiquidity,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal pure returns (uint256 newLiquidity) {
        // Special case for the very first liquidity addition to an empty pool.
        // Liquidity is based on the geometric mean of deposited amounts.
        if (_totalLiquidity == 0) {
            newLiquidity = _sqrt(_amount0 * _amount1);
            // Ensure sufficient initial liquidity to prevent manipulation.
            require(newLiquidity > MINIMUM_LIQUIDITY, "SimpleSwap: INSUFFICIENT_INITIAL_LIQUIDITY");
            // Subtract MINIMUM_LIQUIDITY here, as it's typically burned to address(0)
            // to prevent ratio manipulation on very small initial liquidity.
            newLiquidity -= MINIMUM_LIQUIDITY;
        } else {
            // For subsequent liquidity additions, calculate new liquidity based on proportionality
            // to existing reserves and total supply. Take the minimum to maintain the ratio.
            uint256 liquidity0 = (_amount0 * _totalLiquidity) / _reserve0;
            uint256 liquidity1 = (_amount1 * _totalLiquidity) / _reserve1;
            newLiquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }
        // Ensure a positive amount of new LP tokens is minted.
        require(newLiquidity > 0, "SimpleSwap: NEW_LIQUIDITY_IS_ZERO");
    }

    // --- Main Public/External Functions ---

    /**
     * @dev Allows users to add liquidity to the token pair pool.
     * Users provide desired amounts of tokenA and tokenB, and receive LP tokens in return.
     * The actual amounts deposited will be proportional to current pool reserves.
     * Includes slippage protection via minimum acceptable amounts.
     * @param tokenA The address of the first token (can be token0 or token1).
     * @param tokenB The address of the second token (can be token0 or token1).
     * @param amountADesired Desired amount of tokenA to contribute.
     * @param amountBDesired Desired amount of tokenB to contribute.
     * @param amountAMin Minimum acceptable amount of tokenA to be added, for slippage protection.
     * @param amountBMin Minimum acceptable amount of tokenB to be added, for slippage protection.
     * @param to The recipient address for the minted LP tokens.
     * @param deadline Unix timestamp after which the transaction will revert if not executed.
     * @return amountA The actual amount of tokenA added to the pool.
     * @return amountB The actual amount of tokenB added to the pool.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // --- Checks ---
        // Ensure transaction is not expired
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");
        // Ensure the provided token pair matches the contract's pair
        require(
            (tokenA == token0 && tokenB == token1) || (tokenA == token1 && tokenB == token0),
            "SimpleSwap: INVALID_TOKEN_PAIR"
        );
        // Ensure the recipient address is not zero
        require(to != address(0), "SimpleSwap: ZERO_ADDRESS_TO");

        // Determine if tokenA corresponds to token0 for consistent handling of amounts
        bool isToken0_A = (tokenA == token0);

        // Map desired and min amounts to token0 and token1 based on sorting
        uint256 actualAmount0Desired = isToken0_A ? amountADesired : amountBDesired;
        uint256 actualAmount1Desired = isToken0_A ? amountBDesired : amountADesired;
        uint256 actualAmount0Min = isToken0_A ? amountAMin : amountBMin;
        uint256 actualAmount1Min = isToken0_A ? amountBMin : amountAMin;

        // Calculate optimal amounts of tokens to deposit based on current reserves' ratio
        (uint256 amount0ToDeposit, uint256 amount1ToDeposit) = _calculateOptimalAmounts(
            actualAmount0Desired,
            actualAmount1Desired,
            reserve0,
            reserve1
        );

        // Crucial minimum amount validations (slippage protection):
        // Ensure that the actual amounts determined to deposit are not less than the user's acceptable minimums.
        require(amount0ToDeposit >= actualAmount0Min, "SimpleSwap: AMOUNT_0_TOO_LOW");
        require(amount1ToDeposit >= actualAmount1Min, "SimpleSwap: AMOUNT_1_TOO_LOW");

        // --- Effects & Interactions ---
        // Transfer tokens from the user's address to the contract's reserves.
        // SafeERC20's safeTransferFrom ensures successful transfer and handles ERC-20 return values.
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0ToDeposit);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1ToDeposit);

        // Calculate the amount of new LP tokens to mint based on deposited amounts and current pool state.
        uint256 mintedLiquidity = _calculateLiquidityToMint(
            amount0ToDeposit,
            amount1ToDeposit,
            totalLiquidity,
            reserve0,
            reserve1
        );

        // Handle the burning of MINIMUM_LIQUIDITY when the pool is first initialized.
        // This effectively assigns MINIMUM_LIQUIDITY to address(0) to prevent initial ratio manipulation.
        if (totalLiquidity == 0) {
            liquidityBalances[address(0)] = MINIMUM_LIQUIDITY;
            totalLiquidity = MINIMUM_LIQUIDITY; // Set initial total liquidity to the burned amount.
        }

        // Update total liquidity supply and the provider's LP token balance.
        totalLiquidity += mintedLiquidity;
        liquidityBalances[to] += mintedLiquidity;

        // Update pool reserves with the newly deposited amounts using the _update function.
        // This is done after token transfers and LP token minting (Checks-Effects-Interactions pattern).
        _update(reserve0 + amount0ToDeposit, reserve1 + amount1ToDeposit);

        // Assign return values (amounts based on the initial tokenA/tokenB order)
        amountA = isToken0_A ? amount0ToDeposit : amount1ToDeposit;
        amountB = isToken0_A ? amount1ToDeposit : amount0ToDeposit;
        liquidity = mintedLiquidity;

        // Emit event for liquidity addition for off-chain indexing and monitoring.
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /**
     * @dev Allows users to withdraw liquidity from the token pair pool.
     * Users burn their LP tokens and receive proportional amounts of token0 and token1 from the pool.
     * Includes slippage protection via minimum acceptable amounts.
     * @param tokenA Address of the first token in the pair (can be token0 or token1).
     * @param tokenB Address of the second token in the pair (can be token0 or token1).
     * @param liquidity The amount of LP tokens to burn.
     * @param amountAMin The minimum acceptable amount of tokenA to receive, for slippage protection.
     * @param amountBMin The minimum acceptable amount of tokenB to receive, for slippage protection.
     * @param to The address to send the received tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amountA The actual amount of tokenA received.
     * @return amountB The actual amount of tokenB received.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        // --- Checks ---
        // Ensure transaction is not expired.
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");
        // Ensure the provided token pair matches the contract's pair.
        require((tokenA == token0 && tokenB == token1) || (tokenA == token1 && tokenB == token0), "SimpleSwap: INVALID_TOKEN_PAIR");
        // Ensure the recipient address is not zero.
        require(to != address(0), "SimpleSwap: ZERO_ADDRESS_TO");
        // Ensure a positive amount of LP tokens is specified for removal.
        require(liquidity > 0, "SimpleSwap: INVALID_LIQUIDITY");
        // Ensure the sender has enough LP tokens.
        require(liquidityBalances[msg.sender] >= liquidity, "SimpleSwap: INSUFFICIENT_BALANCE");
        // Ensure there's enough total liquidity in the pool remaining after burning,
        // specifically ensuring MINIMUM_LIQUIDITY is always preserved.
        require(totalLiquidity > MINIMUM_LIQUIDITY, "SimpleSwap: NOT_ENOUGH_LIQUIDITY_TO_REMOVE");

        // Calculate proportional amounts of tokens to withdraw based on burned liquidity.
        // These calculations use the current reserves and total liquidity to maintain the correct ratio.
        uint256 amount0ToWithdraw = (liquidity * reserve0) / totalLiquidity;
        uint256 amount1ToWithdraw = (liquidity * reserve1) / totalLiquidity;

        // Determine if tokenA corresponds to token0 for consistent handling of min amounts.
        bool isToken0_A = (tokenA == token0);
        uint256 actualAmount0Min = isToken0_A ? amountAMin : amountBMin;
        uint256 actualAmount1Min = isToken0_A ? amountBMin : amountAMin;

        // Crucial minimum amount validations (slippage protection):
        // Ensure that the calculated amounts to withdraw are not less than the user's acceptable minimums.
        require(amount0ToWithdraw >= actualAmount0Min, "SimpleSwap: INSUFFICIENT_AMOUNT_0_WITHDRAWN");
        require(amount1ToWithdraw >= actualAmount1Min, "SimpleSwap: INSUFFICIENT_AMOUNT_1_WITHDRAWN");

        // --- Effects & Interactions ---
        // Update LP token balances for the sender and total supply *before* external transfers.
        // This follows the Checks-Effects-Interactions pattern to prevent reentrancy.
        liquidityBalances[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;

        // Update reserves *before* external transfers.
        _update(reserve0 - amount0ToWithdraw, reserve1 - amount1ToWithdraw);

        // Transfer withdrawn tokens to the recipient. SafeERC20 functions ensure proper handling.
        IERC20(token0).safeTransfer(to, amount0ToWithdraw);
        IERC20(token1).safeTransfer(to, amount1ToWithdraw);
        
        // Assign return values (amounts based on the initial tokenA/tokenB order).
        amountA = isToken0_A ? amount0ToWithdraw : amount1ToWithdraw;
        amountB = isToken0_A ? amount1ToWithdraw : amount0ToWithdraw;

        // Emit event for liquidity removal.
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /**
     * @dev Internal helper function to perform the core swap calculation and determine new reserves.
     * This function was refactored to reduce stack depth in `swapExactTokensForTokens`,
     * helping to resolve "Stack too deep" compiler errors. It is `view` because it only reads
     * state variables (`reserve0`, `reserve1`) but doesn't modify them directly.
     * @param amountIn The amount of input tokens to swap.
     * @param _tokenIn The address of the input token.
     * @param _tokenOut The address of the output token.
     * @return _amountOut The calculated amount of output tokens.
     * @return _newReserve0 The new balance of token0 after the swap.
     * @return _newReserve1 The new balance of token1 after the swap.
     */
    function _performSwapCalculation(
        uint256 amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view returns (uint256 _amountOut, uint256 _newReserve0, uint256 _newReserve1) {
        uint256 currentReserveIn;
        uint256 currentReserveOut;

        // Determine current reserves based on which token is the input.
        if (_tokenIn == token0) {
            currentReserveIn = reserve0;
            currentReserveOut = reserve1;
        } else {
            currentReserveIn = reserve1;
            currentReserveOut = reserve0;
        }

        // Calculate the amount of output tokens using the constant product formula with the swap fee.
        // (x + amountInWithFee) * (y - amountOut) = x * y (approximately, considering fee)
        // amountOut = (amountIn * SWAP_FEE_NUMERATOR * currentReserveOut) / (currentReserveIn * SWAP_FEE_DENOMINATOR + amountIn * SWAP_FEE_NUMERATOR)
        uint256 amountInWithFee = amountIn * SWAP_FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * currentReserveOut;
        uint256 denominator = (currentReserveIn * SWAP_FEE_DENOMINATOR) + amountInWithFee;
        _amountOut = numerator / denominator;

        // Calculate new reserves based on the swap.
        // These are provisional values to be passed back for state update.
        if (_tokenIn == token0) {
            _newReserve0 = currentReserveIn + amountIn;
            _newReserve1 = currentReserveOut - _amountOut;
        } else {
            _newReserve0 = currentReserveOut - _amountOut;
            _newReserve1 = currentReserveIn + amountIn;
        }
    }


    /**
     * @dev Swaps an exact amount of input tokens for as many output tokens as possible.
     * This function supports only the single token pair (token0/token1) defined at deployment.
     * It uses the constant product formula and includes a 0.3% swap fee.
     * @param amountIn Amount of input tokens to swap.
     * @param amountOutMin Minimum amount of output tokens expected (slippage protection).
     * @param path Token path: must be an array of two addresses [tokenIn, tokenOut], as only one pair is supported.
     * @param to Address that receives the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts An array with [amountIn, amountOut] for transparency.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path, // Defines the token pair for the swap.
        address to, // Recipient of the swapped tokens.
        uint256 deadline // Transaction expiry timestamp.
    ) external returns (uint256[] memory amounts) {
        // --- Checks ---
        // Ensure transaction has not expired.
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");
        // Path must contain exactly two token addresses (input and output).
        require(path.length == 2, "SimpleSwap: INVALID_PATH");
        // Input amount must be positive.
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        // Recipient address cannot be the zero address.
        require(to != address(0), "SimpleSwap: ZERO_ADDRESS_TO");

        address tokenIn = path[0];
        address tokenOut = path[1];

        // Ensure the provided token pair matches the contract's fixed pair.
        require(
            (tokenIn == token0 && tokenOut == token1) || (tokenIn == token1 && tokenOut == token0),
            "SimpleSwap: INVALID_TOKEN_PAIR"
        );
        // Ensure input and output tokens are not the same.
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_SWAP_TOKENS");
        // Ensure the pool has liquidity for the swap to proceed.
        require(reserve0 > 0 && reserve1 > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_FOR_SWAP");

        // --- Effects & Interactions (Following Checks-Effects-Interactions Pattern) ---
        // Transfer input tokens from the user to the contract's reserves.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Call the auxiliary function to perform the core swap calculation and get new reserve values.
        // This helps manage stack depth.
        (uint256 calculatedAmountOut, uint256 newReserve0, uint256 newReserve1) =
            _performSwapCalculation(amountIn, tokenIn, tokenOut);

        // Slippage protection: Ensure the calculated output amount meets the user's minimum expectation.
        require(calculatedAmountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        // Update the contract's reserve state with the new values.
        // This is done before the external transfer of output tokens.
        _update(newReserve0, newReserve1);

        // Transfer the calculated output tokens to the recipient.
        IERC20(tokenOut).safeTransfer(to, calculatedAmountOut);

        // Prepare return array with input and output amounts for transparency.
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = calculatedAmountOut;

        // Emit a Swap event for off-chain indexing and monitoring.
        emit Swap(msg.sender, amountIn, calculatedAmountOut, tokenIn, tokenOut);

        return amounts; // Return the amounts.
    }

    /**
     * @dev Calculates the price of one token in terms of the other based on current reserves.
     * The price is returned with 1e18 precision (similar to how prices are often represented
     * for tokens with 18 decimal places on Uniswap or other DeFi platforms).
     * @param _tokenA The address of the token for which to get the price (e.g., token0).
     * @param _tokenB The address of the token against which the price is calculated (e.g., token1).
     * @return price The price of _tokenA in terms of _tokenB with 1e18 precision.
     */
    function getPrice(address _tokenA, address _tokenB) external view
    returns (uint256 price){
        // Ensure the provided token pair matches the contract's pair.
        require((_tokenA == token0 && _tokenB == token1) || (_tokenA == token1 && _tokenB == token0), "SimpleSwap: INVALID_TOKEN_PAIR");
        // Ensure there is liquidity in the pool before calculating price.
        require(reserve0 > 0 && reserve1 > 0, "SimpleSwap: NO_LIQUIDITY");

        // Calculate price based on which token is _tokenA.
        // Price of token0 in terms of token1 = reserve1 / reserve0
        // Price of token1 in terms of token0 = reserve0 / reserve1
        // Multiplied by 1e18 for fixed-point precision (common for token prices).
        if (_tokenA == token0) {
            price = (reserve1 * 1e18) / reserve0;
        } else {
            price = (reserve0 * 1e18) / reserve1;
        }
    }

    /**
     * @dev Calculates the amount of output tokens received for a given input amount and reserves.
     * This function is pure (does not read or modify contract state) and includes the swap fee.
     * It's useful for clients to estimate swap outcomes before sending a transaction.
     * @param amountIn The amount of input tokens.
     * @param reserveIn The current reserve balance of the input token.
     * @param reserveOut The current reserve balance of the output token.
     * @return amountOut The calculated amount of output tokens.
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure
    returns (uint256 amountOut){
        // Ensure input amount is positive.
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        // Ensure both reserves are positive for calculation.
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_FOR_CALCULATION");

        // Apply swap fee to the input amount.
        uint256 amountInWithFee = amountIn * SWAP_FEE_NUMERATOR;
        // Calculate numerator for constant product formula.
        uint256 numerator = amountInWithFee * reserveOut;
        // Calculate denominator for constant product formula, including fee.
        uint256 denominator = (reserveIn * SWAP_FEE_DENOMINATOR) + amountInWithFee;
        // Final calculated output amount.
        amountOut = numerator / denominator;
    }
}