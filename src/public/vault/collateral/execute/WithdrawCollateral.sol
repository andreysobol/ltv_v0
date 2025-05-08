// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import '../max/MaxWithdrawCollateral.sol';
import '../../../../state_transition/VaultStateTransition.sol';
import '../../../../state_transition/ERC20.sol';
import '../../../../state_transition/ApplyMaxGrowthFee.sol';
import '../../../../state_transition/MintProtocolRewards.sol';
import '../../../../state_transition/Lending.sol';
import 'src/events/IERC4626Events.sol';
import '../preview/PreviewWithdrawCollateral.sol';
import '../../../../math2/NextStep.sol';

abstract contract WithdrawCollateral is MaxWithdrawCollateral, ApplyMaxGrowthFee, MintProtocolRewards, Lending, VaultStateTransition, IERC4626Events {
    using uMulDiv for uint256;

    error ExceedsMaxWithdrawCollateral(address owner, uint256 assets, uint256 max);

    function withdrawCollateral(uint256 assets, address receiver, address owner) external isFunctionAllowed nonReentrant returns (uint256) {
        MaxWithdrawRedeemCollateralVaultState memory state = maxWithdrawRedeemCollateralVaultState(owner);
        MaxWithdrawRedeemCollateralVaultData memory data = maxWithdrawRedeemCollateralVaultStateToMaxWithdrawRedeemCollateralVaultData(state);
        uint256 max = _maxWithdrawCollateral(data);
        require(assets <= max, ExceedsMaxWithdrawCollateral(owner, assets, max));

        (uint256 shares, DeltaFuture memory deltaFuture) = _previewWithdrawCollateral(assets, data.previewCollateralVaultData);

        if (shares == 0) {
            return 0;
        }

        if (owner != receiver) {
            allowance[owner][receiver] -= shares;
        }

        uint256 withdrawTotalAssets = _totalAssets(
            false,
            TotalAssetsData({
                collateral: data.previewCollateralVaultData.collateral,
                borrow: data.previewCollateralVaultData.borrow,
                borrowPrice: state.previewVaultState.maxGrowthFeeState.totalAssetsState.borrowPrice
            })
        );

        applyMaxGrowthFee(data.previewCollateralVaultData.supplyAfterFee, withdrawTotalAssets);

        _mintProtocolRewards(
            MintProtocolRewardsData({
                deltaProtocolFutureRewardBorrow: deltaFuture.deltaProtocolFutureRewardBorrow,
                deltaProtocolFutureRewardCollateral: deltaFuture.deltaProtocolFutureRewardCollateral,
                supply: data.previewCollateralVaultData.supplyAfterFee,
                totalAppropriateAssets: data.previewCollateralVaultData.totalAssetsCollateral,
                assetPrice: data.previewCollateralVaultData.collateralPrice
            })
        );

        _burn(owner, shares);

        withdraw(assets);

        NextState memory nextState = NextStep.calculateNextStep(
            NextStepData({
                futureBorrow: data.previewCollateralVaultData.futureBorrow,
                futureCollateral: data.previewCollateralVaultData.futureCollateral,
                futureRewardBorrow: data.previewCollateralVaultData.userFutureRewardBorrow +
                    data.previewCollateralVaultData.protocolFutureRewardBorrow,
                futureRewardCollateral: data.previewCollateralVaultData.userFutureRewardCollateral +
                    data.previewCollateralVaultData.protocolFutureRewardCollateral,
                deltaFutureBorrow: deltaFuture.deltaFutureBorrow,
                deltaFutureCollateral: deltaFuture.deltaFutureCollateral,
                deltaFuturePaymentBorrow: deltaFuture.deltaFuturePaymentBorrow,
                deltaFuturePaymentCollateral: deltaFuture.deltaFuturePaymentCollateral,
                deltaUserFutureRewardBorrow: deltaFuture.deltaUserFutureRewardBorrow,
                deltaUserFutureRewardCollateral: deltaFuture.deltaUserFutureRewardCollateral,
                deltaProtocolFutureRewardBorrow: deltaFuture.deltaProtocolFutureRewardBorrow,
                deltaProtocolFutureRewardCollateral: deltaFuture.deltaProtocolFutureRewardCollateral,
                blockNumber: block.number,
                auctionStep: CommonMath.calculateAuctionStep(startAuction, block.number)
            })
        );

        applyStateTransition(
            NextStateData({
                nextState: nextState,
                borrowPrice: state.previewVaultState.maxGrowthFeeState.totalAssetsState.borrowPrice,
                collateralPrice: data.previewCollateralVaultData.collateralPrice
            })
        );

        collateralToken.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }
}
