// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../Constants.sol";
import "../ERC20.sol";
import "../Lending.sol";
import "../math/NextStep.sol";
import "../StateTransition.sol";
import './MaxMint.sol';
import '../ERC4626Events.sol';

abstract contract Mint is MaxMint, ERC20, StateTransition, Lending, NextStep, ERC4626Events {

    using uMulDiv for uint256;

    error ExceedsMaxMint(address receiver, uint256 shares, uint256 max);

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        uint256 max = maxMint(address(receiver));
        require(shares <= max, ExceedsMaxMint(receiver, shares, max));

        uint256 sharesInAssets = shares.mulDivDown(totalAssets(), totalSupply());
        uint256 sharesInUnderlying = sharesInAssets.mulDivDown(getPrices().borrow, Constants.ORACLE_DIVIDER);
        (int256 assetsInUnderlying, DeltaFuture memory deltaFuture) = calculateMintRedeem(int256(sharesInUnderlying), true);
        // int256 signedShares = previewMintRedeem(-1*int256(assets));

        if (assetsInUnderlying > 0) {
            return 0;
        }

        assets = uint256(-assetsInUnderlying).mulDivDown(Constants.ORACLE_DIVIDER, getPrices().borrow);

        // TODO: double check that Token should be transfered from msg.sender or from receiver
        borrowToken.transferFrom(msg.sender, address(this), assets);
        
        if (deltaFuture.deltaProtocolFutureRewardBorrow < 0) {
            _mint(FEE_COLLECTOR, underlyingToShares(uint256(-deltaFuture.deltaProtocolFutureRewardBorrow)));
        }

        if (deltaFuture.deltaProtocolFutureRewardCollateral > 0) {
            _mint(FEE_COLLECTOR, underlyingToShares(uint256(deltaFuture.deltaProtocolFutureRewardCollateral)));
        }

        repay(assets);

        // TODO: fix this - return from calculateDepositWithdraw
        ConvertedAssets memory convertedAssets = recoverConvertedAssets();

        NextState memory nextState = calculateNextStep(convertedAssets, deltaFuture, block.number);

        applyStateTransition(nextState);

        emit Deposit(msg.sender, receiver, assets, shares);

        _mint(receiver, shares);

        return assets;
    }

}
