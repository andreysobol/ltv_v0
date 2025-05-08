// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import '../max/MaxRedeem.sol';
import '../../../../state_transition/VaultStateTransition.sol';
import '../../../../state_transition/ERC20.sol';
import '../../../../state_transition/ApplyMaxGrowthFee.sol';
import '../../../../state_transition/MintProtocolRewards.sol';
import '../../../../state_transition/Lending.sol';
import 'src/events/IERC4626Events.sol';
import '../preview/PreviewRedeem.sol';
import '../../../../math2/NextStep.sol';
import '../../../../state_transition/TransferFromProtocol.sol';

abstract contract Redeem is MaxRedeem, ApplyMaxGrowthFee, MintProtocolRewards, Lending, VaultStateTransition, TransferFromProtocol, IERC4626Events {
    using uMulDiv for uint256;

    error ExceedsMaxRedeem(address owner, uint256 shares, uint256 max);

    function redeem(uint256 shares, address receiver, address owner) external isFunctionAllowed nonReentrant returns (uint256 assets) {
        MaxWithdrawRedeemBorrowVaultState memory state = maxWithdrawRedeemBorrowVaultState(owner);
        MaxWithdrawRedeemBorrowVaultData memory data = maxWithdrawRedeemBorrowVaultStateToMaxWithdrawRedeemBorrowVaultData(state);
        uint256 max = _maxRedeem(data);
        require(shares <= max, ExceedsMaxRedeem(owner, shares, max));

        if (owner != receiver) {
            allowance[owner][receiver] -= shares;
        }

        (uint256 assetsOut, DeltaFuture memory deltaFuture) = _previewRedeem(shares, data.previewBorrowVaultData);

        if (assetsOut == 0) {
            return 0;
        }

        applyMaxGrowthFee(data.previewBorrowVaultData.supplyAfterFee, totalAssets(true, state.previewVaultState.maxGrowthFeeState.totalAssetsState));

        _mintProtocolRewards(
            MintProtocolRewardsData({
                deltaProtocolFutureRewardBorrow: deltaFuture.deltaProtocolFutureRewardBorrow,
                deltaProtocolFutureRewardCollateral: deltaFuture.deltaProtocolFutureRewardCollateral,
                supply: data.previewBorrowVaultData.supplyAfterFee,
                totalAppropriateAssets: data.previewBorrowVaultData.totalAssets,
                assetPrice: data.previewBorrowVaultData.borrowPrice
            })
        );

        _burn(owner, shares);

        NextState memory nextState = NextStep.calculateNextStep(
            NextStepData({
                futureBorrow: data.previewBorrowVaultData.futureBorrow,
                futureCollateral: data.previewBorrowVaultData.futureCollateral,
                futureRewardBorrow: data.previewBorrowVaultData.userFutureRewardBorrow + data.previewBorrowVaultData.protocolFutureRewardBorrow,
                futureRewardCollateral: data.previewBorrowVaultData.userFutureRewardCollateral +
                    data.previewBorrowVaultData.protocolFutureRewardCollateral,
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
                borrowPrice: data.previewBorrowVaultData.borrowPrice,
                collateralPrice: state.previewVaultState.maxGrowthFeeState.totalAssetsState.collateralPrice
            })
        );

        borrow(assetsOut);

        transferBorrowToken(receiver, assetsOut);

        emit Withdraw(msg.sender, receiver, owner, assetsOut, shares);

        return assetsOut;
    }
}
