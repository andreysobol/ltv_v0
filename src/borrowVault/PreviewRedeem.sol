// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../Constants.sol";
import "./TotalAssets.sol";
import "../math/MintRedeemBorrow.sol";
import "../math/DepositWithdrawBorrow.sol";

abstract contract PreviewRedeem is TotalAssets, DepositWithdrawBorrow, MintRedeemBorrow {

    using uMulDiv for uint256;

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        uint256 sharesInAssets = shares.mulDivUp(totalAssets(), totalSupply());
        uint256 sharesInUnderlying = sharesInAssets.mulDivUp(getPrices().borrow, Constants.ORACLE_DIVIDER);
        int256 assetsInUnderlying = previewMintRedeemBorrow(-1*int256(sharesInUnderlying));

        if (assetsInUnderlying < 0) {
            return 0;
        }

        return uint256(assetsInUnderlying).mulDivDown(Constants.ORACLE_DIVIDER, getPrices().borrow);
    }

}
