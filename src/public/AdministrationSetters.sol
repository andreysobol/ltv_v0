// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "src/Constants.sol";
import "src/states/LTVState.sol";
import "src/utils/MulDiv.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "src/state_transition/Lending.sol";
import "src/errors/IAdministrationErrors.sol";
import "src/modifiers/AdministrationModifiers.sol";
import "src/events/IAdministrationEvents.sol";
import "src/modifiers/FunctionStopperModifier.sol";
import "../math/MaxGrowthFee.sol";
import "../state_reader/MaxGrowthFeeStateReader.sol";
import "../state_transition/ApplyMaxGrowthFee.sol";

abstract contract AdministrationSetters is
    ApplyMaxGrowthFee,
    MaxGrowthFee,
    MaxGrowthFeeStateReader,
    Lending,
    AdministrationModifiers,
    IAdministrationEvents
{
    using uMulDiv for uint256;
    using sMulDiv for int256;

    function setTargetLTV(uint128 value) external isFunctionAllowed onlyGovernor {
        require(value > 0 && value < Constants.LTV_DIVIDER, UnexpectedTargetLTV(value));
        require(value <= maxSafeLTV && value >= minProfitLTV, InvalidLTVSet(value, maxSafeLTV, minProfitLTV));
        uint128 oldValue = targetLTV;
        targetLTV = value;
        emit TargetLTVChanged(oldValue, targetLTV);
    }

    function setMaxSafeLTV(uint128 value) external isFunctionAllowed onlyGovernor {
        require(value > 0 && value < Constants.LTV_DIVIDER, UnexpectedMaxSafeLTV(value));
        require(value >= targetLTV, InvalidLTVSet(targetLTV, value, minProfitLTV));
        uint128 oldValue = maxSafeLTV;
        maxSafeLTV = value;
        emit MaxSafeLTVChanged(oldValue, value);
    }

    function setMinProfitLTV(uint128 value) external isFunctionAllowed onlyGovernor {
        require(value > 0 && value < Constants.LTV_DIVIDER, UnexpectedMinProfitLTV(value));
        require(value <= targetLTV, InvalidLTVSet(targetLTV, maxSafeLTV, value));
        uint128 oldValue = minProfitLTV;
        minProfitLTV = value;
        emit MinProfitLTVChanged(oldValue, value);
    }

    function setFeeCollector(address _feeCollector) external isFunctionAllowed onlyGovernor {
        require(_feeCollector != address(0), ZeroFeeCollector());
        address oldFeeCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldFeeCollector, _feeCollector);
    }

    function setMaxTotalAssetsInUnderlying(uint256 _maxTotalAssetsInUnderlying)
        external
        isFunctionAllowed
        onlyGovernor
    {
        uint256 oldValue = maxTotalAssetsInUnderlying;
        maxTotalAssetsInUnderlying = _maxTotalAssetsInUnderlying;
        emit MaxTotalAssetsInUnderlyingChanged(oldValue, _maxTotalAssetsInUnderlying);
    }

    function setMaxDeleverageFee(uint256 value) external isFunctionAllowed onlyGovernor {
        require(value <= 10 ** 18, InvalidMaxDeleverageFee(value));
        uint256 oldValue = maxDeleverageFee;
        maxDeleverageFee = value;
        emit MaxDeleverageFeeChanged(oldValue, value);
    }

    function setIsWhitelistActivated(bool activate) external isFunctionAllowed onlyGovernor {
        require(!activate || address(whitelistRegistry) != address(0), WhitelistRegistryNotSet());
        bool oldValue = isWhitelistActivated;
        isWhitelistActivated = activate;
        emit IsWhitelistActivatedChanged(oldValue, activate);
    }

    function setWhitelistRegistry(IWhitelistRegistry value) external isFunctionAllowed onlyGovernor {
        require(address(value) != address(0) || !isWhitelistActivated, WhitelistIsActivated());
        address oldAddress = address(whitelistRegistry);
        whitelistRegistry = value;
        emit WhitelistRegistryUpdated(oldAddress, address(value));
    }

    function setSlippageProvider(ISlippageProvider _slippageProvider) external isFunctionAllowed onlyGovernor {
        require(address(_slippageProvider) != address(0), ZeroSlippageProvider());
        address oldAddress = address(slippageProvider);
        slippageProvider = _slippageProvider;
        emit SlippageProviderUpdated(oldAddress, address(_slippageProvider));
    }

    // batch can be removed to save ~250 bytes of contract size
    function allowDisableFunctions(bytes4[] memory signatures, bool isDisabled) external onlyGuardian {
        for (uint256 i = 0; i < signatures.length; i++) {
            _isFunctionDisabled[signatures[i]] = isDisabled;
        }
    }

    function setMaxGrowthFee(uint256 _maxGrowthFee) external isFunctionAllowed onlyGovernor {
        require(_maxGrowthFee <= 10 ** 18, InvalidMaxGrowthFee(_maxGrowthFee));
        uint256 oldValue = maxGrowthFee;
        maxGrowthFee = _maxGrowthFee;
        emit MaxGrowthFeeChanged(oldValue, _maxGrowthFee);
    }

    function setVaultBalanceAsLendingConnector(address _vaultBalanceAsLendingConnector) external onlyOwner {
        address oldAddress = address(vaultBalanceAsLendingConnector);
        vaultBalanceAsLendingConnector = ILendingConnector(_vaultBalanceAsLendingConnector);
        emit VaultBalanceAsLendingConnectorUpdated(oldAddress, _vaultBalanceAsLendingConnector);
    }

    function setIsDepositDisabled(bool value) external onlyGuardian {
        bool oldValue = isDepositDisabled;
        isDepositDisabled = value;
        emit IsDepositDisabledChanged(oldValue, value);
    }

    function setIsWithdrawDisabled(bool value) external onlyGuardian {
        bool oldValue = isWithdrawDisabled;
        isWithdrawDisabled = value;
        emit IsWithdrawDisabledChanged(oldValue, value);
    }

    function setLendingConnector(ILendingConnector _lendingConnector) external onlyOwner {
        address oldAddress = address(lendingConnector);
        lendingConnector = _lendingConnector;
        emit LendingConnectorUpdated(oldAddress, address(_lendingConnector));
    }

    function setOracleConnector(IOracleConnector _oracleConnector) external onlyOwner {
        address oldAddress = address(oracleConnector);
        oracleConnector = _oracleConnector;
        emit OracleConnectorUpdated(oldAddress, address(_oracleConnector));
    }

    function deleverageAndWithdraw(uint256 closeAmountBorrow, uint256 deleverageFee)
        external
        onlyEmergencyDeleverager
        nonReentrant
    {
        require(deleverageFee <= maxDeleverageFee, ExceedsMaxDeleverageFee(deleverageFee, maxDeleverageFee));
        require(!isVaultDeleveraged, VaultAlreadyDeleveraged());
        require(address(vaultBalanceAsLendingConnector) != address(0), VaultBalanceAsLendingConnectorNotSet());

        MaxGrowthFeeState memory state = maxGrowthFeeState();
        MaxGrowthFeeData memory data = maxGrowthFeeStateToData(state);

        applyMaxGrowthFee(_previewSupplyAfterFee(data), data.withdrawTotalAssets);

        futureBorrowAssets = 0;
        futureCollateralAssets = 0;
        futureRewardBorrowAssets = 0;
        futureRewardCollateralAssets = 0;
        startAuction = 0;
        minProfitLTV = 0;
        targetLTV = 0;
        maxSafeLTV = uint128(Constants.LTV_DIVIDER);

        // round up to repay all assets
        uint256 realBorrowAssets = lendingConnector.getRealBorrowAssets(false);

        require(closeAmountBorrow >= realBorrowAssets, ImpossibleToCoverDeleverage(realBorrowAssets, closeAmountBorrow));

        uint256 collateralAssets = lendingConnector.getRealCollateralAssets(false);

        uint256 collateralToTransfer = realBorrowAssets.mulDivDown(
            oracleConnector.getPriceBorrowOracle(), oracleConnector.getPriceCollateralOracle()
        );

        collateralToTransfer +=
            (collateralAssets - collateralToTransfer).mulDivDown(deleverageFee, Constants.MAX_GROWTH_FEE_DIVIDER);

        if (realBorrowAssets != 0) {
            borrowToken.transferFrom(msg.sender, address(this), realBorrowAssets);
            repay(realBorrowAssets);
        }

        withdraw(collateralAssets);

        if (collateralToTransfer != 0) {
            collateralToken.transfer(msg.sender, collateralToTransfer);
        }
        isVaultDeleveraged = true;
    }

    function updateEmergencyDeleverager(address newEmergencyDeleverager) external onlyOwner {
        address oldEmergencyDeleverager = emergencyDeleverager;
        emergencyDeleverager = newEmergencyDeleverager;
        emit EmergencyDeleveragerUpdated(oldEmergencyDeleverager, newEmergencyDeleverager);
    }

    function updateGovernor(address newGovernor) external onlyOwner {
        address oldGovernor = governor;
        governor = newGovernor;
        emit GovernorUpdated(oldGovernor, newGovernor);
    }

    function updateGuardian(address newGuardian) external onlyOwner {
        address oldGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(oldGuardian, newGuardian);
    }
}
