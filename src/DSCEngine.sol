// SPDX-License-Identifier: MIT

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma solidity 0.8.19;

/**
 * @title DSCEngine
 * @author Squilliam
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain their a 1 token == $1(USD) peg
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be overcollateralized. At no point, should the value of all collateral be <= the dollar backed value of all the DSC
 *
 * @notice This contract is the core of the DSC System. it handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    //      Errors      //
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSC__BreaksHealthFactor(uint256);
    error DSCEngine__MintFailed();

    // State Variables //

    // Chainlink price feeds return prices with 8 decimal places
    // To maintain precision when working with USD values, we add 10 more decimal places
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    // we use this to divide by 1e18 to get a precise number
    // Example: If we multiply:
    // (2000 * 1e8) * 1e10 * (1 ETH * 1e18) = huge number with too many decimals
    // So we divide by 1e18 (PRECISION) to get back to the correct decimal places
    // Most ERC20s use 18 decimal places, so this helps us standardize our math
    uint256 private constant PRECISION = 1e18;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    uint256 private constant LIQUIDATION_PRECISION = 100;

    // Minimum health factor before user can be liquidated
    // If a user goes below 1, then they can get liquidated
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    // maps token address to pricefeed addresses
    mapping(address token => address priceFeed) private s_priceFeeds;

    // Tracks how much collateral each user has deposited
    // First key: user's address
    // Second key: token address they deposited
    // Value: amount of that token they have deposited
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    // mapping the user to the amount of DSC they have minted
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    // an array of all the collateral tokens users can use.
    address[] private s_collateralTokens;

    // We can't just call DecentralizedStableCoin.mint directly because DecentralizedStableCoin is a contract type, not a deployed contract
    // We need to know the specific address where the contract is deployed to interact with it
    // we set the address in the constructor of this contract
    DecentralizedStableCoin private immutable i_dsc;

    //       Events      //
    // Event emitted when collateral is deposited, used for:
    // 1. Off-chain tracking of deposits
    // 2. DApp frontend updates
    // 3. Cheaper storage than writing to state
    // `indexed` parameters allow efficient filtering/searching of logs
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    //    Modifiers    //

    // modifier to make sure that the amount being passes as the input is more than 0 or the function being called will revert.
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // Modifier that checks if a token is in our list of allowed collateral tokens
    // If a token has no price feed address (equals address(0)) in our s_priceFeeds mapping,
    // it means it's not an allowed token and the transaction will revert
    // The underscore (_) means "continue with the function code if check passes"
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //    Functions   //
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // loop through the tokenAddresses array and count it by 1s
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // and we set each tokenAddress equal to their respective priceFeedAddresses in the mapping.
            // we declare this in the constructor and define the variables in the deployment script
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            // push all the tokens into our tokens array/list
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // Initialize our DSC instance by casting the provided address to a DecentralizedStableCoin type
        // This allows us to interact with the DSC contract's functions from within this contract
        // we pass the address in the deployment script
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // External Functions //

    function depositCollateralAndMintDsc() external {}

    /*
    * @notice follows CEI
    * @dev `@param` means the definitions of the parameters that the function takes.
    * @param tokenCollateralAddress: the address of the token that users are depositing as collateral
    * @param amountCollateral: the amount of tokens they are depositing
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // we update state here, so when we update state, we must emit an event.
        // updates the user's balance in our tracking/mapping system by adding their new deposit amount to their existing balance for the specific collateral token they deposited
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        // emit the event of the state update
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Attempt to transfer tokens from the user to this contract
        // 1. IERC20(tokenCollateralAddress): Cast the token address to tell Solidity it's an ERC20 token
        // 2. transferFrom parameters:
        //    - msg.sender: the user who is depositing collateral
        //    - address(this): this DSCEngine contract receiving the collateral
        //    - amountCollateral: how many tokens to transfer
        // 3. This transferFrom function that we are calling returns a bool: true if transfer succeeded, false if it failed, so we capture the result
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        // if it is not successful, then revert.
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
    * @notice: follows CEI
    * @param amountDscToMint: The amount of Decentralized StableCoin to mint
    * @notice: msg.sender must have more collateral value than the minimum threshold
    */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        // update the internal mapping to track how much the msg.sender has minted
        // s_DSCMinted[msg.sender] = s_DSCMinted[msg.sender] + amountDscToMint;
        //above is the old way. below is the shortcut with += . This += means we are adding the new value to the existing value that already exists.
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //    Private & Internal View Functions    //

    /* internal & private functions start with a `_` to let us developers know that they are internal functions */

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        // gets the amount a user has minted and saves it as a variable named totalDscMinted
        totalDscMinted = s_DSCMinted[user];
        // gets the total amount of collateral the user has deposited and saves it has a variable named collateralValueInUsd
        collateralValueInUsd = getAccountCollateralValue(user);
        // returns the users minted DSC amount and the users collateral amount
        return (totalDscMinted, collateralValueInUsd);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) internal view returns (uint256) {
        // Get user's DSC minted amount and total collateral value in USD from _getAccountInformation
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // multiplies the users collateral by 50, then takes the product and divides it by 100 for precision
        // example: 1000 * 50 = 50,000
        // 50,000 / 100 = 500
        // saves the result as a variable named collateralAdjustedForThreshold
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // multiplies the outcome of the equation above by 1e18 and divides the product by how much DSC the user has minted. Returns the result. The result is the healthfactor.
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

        // example:
        // $1000 ETH / 100 DSC
        //1000 * 50 = 50,000 / 100 = (500 / 100) > 1
        // this function returns the user's health factor
    }

    // Check
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // grabs the user's health factor by calling _healthFactor
        uint256 userHealthFactor = _healthFactor(user);
        // if it is less than 1, revert.
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSC__BreaksHealthFactor(userHealthFactor);
        }
    }

    //    Public & External View Functions    //

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each token in our list of accepted collateral tokens
        // i = 0: Start with the first token in the array
        // i < length: Continue until we've checked every token
        // i++: Move to next token after each iteration
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            // Get the token address at the current index (i) from our array of collateral tokens
            // Example: If i = 0, might get WETH address
            // Example: If i = 1, might get WBTC address
            address token = s_collateralTokens[i];

            // Get how much of this specific token the user has deposited as collateral
            // Example: If user has deposited 5 WETH, amount = 5
            // Example: If user has deposited 2 WBTC, amount = 2
            uint256 amount = s_collateralDeposited[user][token];

            // After getting the token and the amount of tokens the user has, gets the correct amount of collateral the user has deposited and saves it as a variable named totalCollateralValueInUsd
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        // return the total amount of collateral in USD
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // gets the priceFeed of the token inputted by the user and saves it as a variable named priceFeed of type AggregatorV3Interface
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // out of all the data that is returned by the pricefeed, we only want to save the price
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Calculate USD value while handling decimal precision:
        // 1. Convert price to uint256 and multiply by ADDITIONAL_FEED_PRECISION to match token decimals
        // 2. Multiply by the token amount
        // 3. Divide by PRECISION to get the final USD value with correct decimal places
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }
}
