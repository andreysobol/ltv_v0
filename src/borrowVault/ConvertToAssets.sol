// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../State.sol";
import "../Constants.sol";
import "../Structs.sol";
import "./TotalAssets.sol";
import "../ERC20.sol";
import "../utils/MulDiv.sol";

abstract contract ConvertToAssets is State, TotalAssets, ERC20 {

    using uMulDiv for uint256;

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return shares.mulDivDown(totalAssets(), totalSupply());
    }
}