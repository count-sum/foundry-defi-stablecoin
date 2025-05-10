// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDsc.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig public config;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountToMint = 100 ether;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/eth = 30,000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // 2000 /eth , $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMorethanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedtoken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockCollateralToken = new MockFailedTransferFrom();
        tokenAddresses = [address(mockCollateralToken)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        mockCollateralToken.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(address(mockCollateralToken)).approve(address(mockDsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockCollateralToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testEmitsCollateralDepositedEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanDepositMultipleCollaterals() public {
        vm.startPrank(USER);

        // Deposit ETH
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Deposit BTC
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);

        vm.stopPrank();

        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        // expected USD value
        uint256 ethValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 btcValue = dsce.getUsdValue(wbtc, AMOUNT_COLLATERAL);
        uint256 expectedValue = ethValue + btcValue;

        assertEq(collateralValueInUsd, expectedValue);
    }

    function testCanDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        // Calculate a safe amount to mint (50% of collateral value)
        uint256 collateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        amountToMint = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100 / 2; // 50% of the allowed minting

        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
        assertEq(dsc.balanceOf(USER), amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 collateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        amountToMint = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100 / 2;
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
        _;
    }

    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMorethanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);

        uint256 collateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        amountToMint = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100 / 2;

        dsce.mintDsc(amountToMint);

        assertEq(dsc.balanceOf(USER), amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        // Setup mock DSC that fails on mint
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        // Set mockDSC's engine address for minting authorization
        mockDsc.transferOwnership(address(mockDsce));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.mintDsc(1e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfBurnAmountIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMorethanZero.selector);
        dsce.burnDSC(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 initialDscBalance = dsc.balanceOf(USER);
        uint256 amountToBurn = initialDscBalance / 2;

        dsc.approve(address(dsce), amountToBurn);
        dsce.burnDSC(amountToBurn);

        uint256 finalDscBalance = dsc.balanceOf(USER);
        assertEq(finalDscBalance, initialDscBalance - amountToBurn);

        (uint256 dscMinted,) = dsce.getAccountInformation(USER);
        assertEq(dscMinted, initialDscBalance - amountToBurn);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMorethanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 initialWethBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 redeemAmount = AMOUNT_COLLATERAL / 2;

        dsce.redeemCollateral(weth, redeemAmount);

        uint256 finalWethBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(finalWethBalance, initialWethBalance + redeemAmount);

        (, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL - redeemAmount);
        assertEq(collateralValueInUsd, expectedCollateralValue);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        MockFailedTransfer mockToken = new MockFailedTransfer();
        tokenAddresses = [address(mockToken)];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        mockToken.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(address(mockToken)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(address(mockToken), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testEmitsCollateralRedeemedEvent() public depositedCollateral {
        vm.startPrank(USER);
        uint256 redeemAmount = AMOUNT_COLLATERAL / 2;

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, redeemAmount);

        dsce.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    REDEEM COLLATERAL FOR DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        (uint256 dscMinted,) = dsce.getAccountInformation(USER);
        uint256 initialWethBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 collateralToRedeem = AMOUNT_COLLATERAL / 2;

        dsc.approve(address(dsce), dscMinted);
        dsce.redeemCollateralForDSC(weth, collateralToRedeem, dscMinted);

        uint256 finalWethBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(finalWethBalance, initialWethBalance + collateralToRedeem);

        uint256 finalDscBalance = dsc.balanceOf(USER);
        assertEq(finalDscBalance, 0);

        (uint256 finalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalDscMinted, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         HEALTH FACTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        (uint256 dscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedHealthFactor = dsce.calculateHealthFactor(dscMinted, collateralValueInUsd);

        // We expect health factor to be greater than MIN_HEALTH_FACTOR since we only minted 50% of allowed amount
        assertTrue(expectedHealthFactor > MIN_HEALTH_FACTOR);
    }

    function testHealthFactorCanBeBroken() public depositedCollateral {
        vm.startPrank(USER);

        // Mint the maximum allowed (will be close to but not breaking health factor)
        uint256 collateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 maxMintAmount = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        dsce.mintDsc(maxMintAmount);

        // Now simulate ETH price drop by updating the price feed
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); // ETH now worth $1000 instead of $2000

        // Calculate new health factor
        (uint256 dscMinted, uint256 newCollateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 newHealthFactor = dsce.calculateHealthFactor(dscMinted, newCollateralValueInUsd);

        // Health factor should be below MIN_HEALTH_FACTOR after price drop
        assertTrue(newHealthFactor < MIN_HEALTH_FACTOR);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfHealthFactorOk() public depositedCollateralAndMintedDsc {
        vm.startPrank(LIQUIDATOR);
        (uint256 dscMinted,) = dsce.getAccountInformation(USER);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, dscMinted);
        vm.stopPrank();
    }

    function testRevertsIfLiquidationAmountIsZero() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMorethanZero.selector);
        dsce.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            TESTING GETTERS
    //////////////////////////////////////////////////////////////*/

    function testGetPrecision() public view {
        uint256 precision = dsce.getPrecision();
        assertEq(precision, 1e18);
    }

    function testGetAdditionalFeedPrecision() public view {
        uint256 additionalFeedPrecision = dsce.getAdditionalFeedPrecision();
        assertEq(additionalFeedPrecision, 1e10);
    }

    function testGetHealthFactor() public view {
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, UINT256_MAX);
    }

    function testGetHealthFactor2() public depositedCollateralAndMintedDsc {
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, 2e18);
    }

    function testGetLiquidationBonus() public view {
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus, 10);
    }

    function testGetLiquidationPrecision() public view {
        uint256 liquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(liquidationPrecision, 100);
    }

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateralAndMintedDsc {
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }
}
