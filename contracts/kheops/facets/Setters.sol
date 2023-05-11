// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Diamond } from "../libraries/Diamond.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";

import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibManager } from "../libraries/LibManager.sol";
import { LibSetters } from "../libraries/LibSetters.sol";
import { LibHelper } from "../libraries/LibHelper.sol";
import { LibRedeemer } from "../libraries/LibRedeemer.sol";
import { AccessControlModifiers } from "../utils/AccessControlModifiers.sol";
import "../../utils/Constants.sol";
import "../../utils/Errors.sol";

import "../Storage.sol";

import { ISetters } from "../interfaces/ISetters.sol";

/// @title Setters
/// @author Angle Labs, Inc.
contract Setters is AccessControlModifiers, ISetters {
    using SafeERC20 for IERC20;

    event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);
    event CollateralRevoked(address indexed collateral);
    event ManagerDataSet(address indexed collateral, ManagerStorage managerData);
    event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);
    event ReservesAdjusted(address indexed collateral, uint256 amount, bool addOrRemove);
    event TrustedToggled(address indexed sender, uint256 trustedStatus, uint8 trustedType);

    /// @inheritdoc ISetters
    function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        bool isManaged = collatInfo.isManaged > 0;
        ManagerStorage memory emptyManagerData;
        LibHelper.transferCollateral(
            isManaged ? address(token) : collateral,
            to,
            amount,
            false,
            isManaged ? collatInfo.managerData : emptyManagerData
        );
    }

    /// @inheritdoc ISetters
    function setAccessControlManager(address _newAccessControlManager) external onlyGovernor {
        LibSetters.setAccessControlManager(IAccessControlManager(_newAccessControlManager));
    }

    /// @inheritdoc ISetters
    function setCollateralManager(address collateral, ManagerStorage memory managerData) external onlyGovernor {
        Collateral storage collatInfo = s.kheopsStorage().collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        uint8 isManaged = collatInfo.isManaged;
        if (isManaged > 0) LibManager.pullAll(collateral, collatInfo.managerData);
        if (managerData.managerConfig.length != 0) collatInfo.isManaged = 1;
        else {
            ManagerStorage memory emptyManagerData;
            managerData = emptyManagerData;
        }
        collatInfo.managerData = managerData;
        emit CollateralManagerSet(collateral, managerData);
    }

    /// @inheritdoc ISetters
    function setManagerData(address collateral, ManagerStorage memory managerData) external onlyGovernor {
        s.kheopsStorage().collaterals[collateral].managerData = managerData;
        emit ManagerDataSet(collateral, managerData);
    }

    /// @inheritdoc ISetters
    function togglePause(address collateral, PauseType pausedType) external onlyGuardian {
        LibSetters.togglePause(collateral, pausedType);
    }

    /// @inheritdoc ISetters
    function toggleTrusted(address sender, uint8 trustedType) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        uint256 trustedStatus;
        if (trustedType == 0) {
            trustedStatus = 1 - ks.isTrusted[sender];
            ks.isTrusted[sender] = trustedStatus;
        } else {
            trustedStatus = 1 - ks.isSellerTrusted[sender];
            ks.isSellerTrusted[sender] = trustedStatus;
        }
        emit TrustedToggled(sender, trustedStatus, trustedType);
    }

    /// @inheritdoc ISetters
    function addCollateral(address collateral) external onlyGovernor {
        LibSetters.addCollateral(collateral);
    }

    /// @inheritdoc ISetters
    /// @dev amount is an absolute amount (like not normalized) -> need to pay attention to this
    /// Why not normalising directly here? easier for Governance
    function adjustReserve(address collateral, uint256 amount, bool addOrRemove) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral storage collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0) revert NotCollateral();
        if (addOrRemove) {
            collatInfo.normalizedStables += amount;
            ks.normalizedStables += amount;
        } else {
            collatInfo.normalizedStables -= amount;
            ks.normalizedStables -= amount;
        }
        emit ReservesAdjusted(collateral, amount, addOrRemove);
    }

    /// @inheritdoc ISetters
    function revokeCollateral(address collateral) external onlyGovernor {
        KheopsStorage storage ks = s.kheopsStorage();
        Collateral memory collatInfo = ks.collaterals[collateral];
        if (collatInfo.decimals == 0 || collatInfo.normalizedStables > 0) revert NotCollateral();
        delete ks.collaterals[collateral];
        address[] memory collateralListMem = ks.collateralList;
        uint256 length = collateralListMem.length;
        for (uint256 i; i < length - 1; ++i) {
            if (collateralListMem[i] == collateral) {
                ks.collateralList[i] = collateralListMem[length - 1];
                break;
            }
        }
        ks.collateralList.pop();
        emit CollateralRevoked(collateral);
    }

    /// @inheritdoc ISetters
    function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external onlyGuardian {
        LibSetters.setFees(collateral, xFee, yFee, mint);
    }

    /// @inheritdoc ISetters
    function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external onlyGuardian {
        KheopsStorage storage ks = s.kheopsStorage();
        LibSetters.checkFees(xFee, yFee, 2);
        ks.xRedemptionCurve = xFee;
        ks.yRedemptionCurve = yFee;
        emit RedemptionCurveParamsSet(xFee, yFee);
    }

    /// @inheritdoc ISetters
    function setOracle(address collateral, bytes memory oracleConfig) external onlyGovernor {
        LibSetters.setOracle(collateral, oracleConfig);
    }

    /// @inheritdoc ISetters
    function updateNormalizer(uint256 amount, bool increase) external returns (uint256) {
        // Trusted addresses can call the function (like a savings contract in the case of a LSD)
        if (!Diamond.isGovernor(msg.sender) && s.kheopsStorage().isTrusted[msg.sender] == 0) revert NotTrusted();
        return LibRedeemer.updateNormalizer(amount, increase);
    }
}
