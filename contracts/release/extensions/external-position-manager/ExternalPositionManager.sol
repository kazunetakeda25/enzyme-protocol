// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    
    (c) Enzyme Council <council@enzyme.finance>
    
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../../core/fund/external-positions/ExternalPositionProxy.sol";
import "../../core/fund/external-positions/IExternalPosition.sol";
import "../../utils/FundDeployerOwnerMixin.sol";
import "../policy-manager/IPolicyManager.sol";
import "../utils/ExtensionBase.sol";
import "../utils/PermissionedVaultActionMixin.sol";
import "./parsers/IExternalPositionParser.sol";

/// @title ExternalPositionManager
/// @author Enzyme Council <security@enzyme.finance>
/// @notice Extension to handle external position actions for funds.
contract ExternalPositionManager is
    ExtensionBase,
    PermissionedVaultActionMixin,
    FundDeployerOwnerMixin
{
    event ExternalPositionDeployed(
        address indexed comptrollerProxy,
        address indexed vaultProxy,
        address externalPosition,
        uint256 externalPositionType,
        bytes data
    );

    struct TypeInfo {
        address parser;
        address lib;
    }

    enum ExternalPositionManagerActions {
        CreateExternalPosition,
        CallOnExternalPosition,
        RemoveExternalPosition
    }

    address private immutable POLICY_MANAGER;

    uint256 private totalTypes;
    mapping(uint256 => TypeInfo) private typeToTypeInfo;

    constructor(address _fundDeployer, address _policyManager)
        public
        FundDeployerOwnerMixin(_fundDeployer)
    {
        POLICY_MANAGER = _policyManager;
    }

    /////////////
    // GENERAL //
    /////////////

    /// @notice Activates the extension by storing the VaultProxy
    function activateForFund(bool) external override {
        __setValidatedVaultProxy(msg.sender);
    }

    /// @notice Receives a dispatched `callOnExtension` from a fund's ComptrollerProxy
    /// @param _caller The user who called for this action
    /// @param _actionId An ID representing the desired action
    /// @param _callArgs The encoded args for the action
    function receiveCallFromComptroller(
        address _caller,
        uint256 _actionId,
        bytes calldata _callArgs
    ) external override {
        address vaultProxy = comptrollerProxyToVaultProxy[msg.sender];
        require(vaultProxy != address(0), "receiveCallFromComptroller: Fund is not active");

        __validateIsFundOwner(vaultProxy, _caller);

        // Dispatch the action
        if (_actionId == uint256(ExternalPositionManagerActions.CreateExternalPosition)) {
            __createExternalPosition(_caller, vaultProxy, _callArgs);
        } else if (_actionId == uint256(ExternalPositionManagerActions.CallOnExternalPosition)) {
            __executeCallOnExternalPosition(_caller, vaultProxy, _callArgs);
        } else if (_actionId == uint256(ExternalPositionManagerActions.RemoveExternalPosition)) {
            __executeRemoveExternalPosition(_caller, _callArgs);
        } else {
            revert("receiveCallFromComptroller: Invalid _actionId");
        }
    }

    ////////////////////
    // TYPES REGISTRY //
    ////////////////////

    /// @notice Creates a new type id and adds the input type info to it
    /// @param _libs Contract libs to be set for the new type id
    /// @param _parsers Parsers to be set for the new type id
    function addTypesInfo(address[] memory _libs, address[] memory _parsers)
        external
        onlyFundDeployerOwner
    {
        __addTypesInfo(_libs, _parsers);
    }

    /// @notice Updates the TypeInfo of the given typeIds
    /// @param _typeIds Ids of the types to be updated
    /// @param _libs Contract libs to be set for the type ids
    /// @param _parsers Parsers to be set for the type ids
    function updateTypesInfo(
        uint256[] memory _typeIds,
        address[] memory _libs,
        address[] memory _parsers
    ) external onlyFundDeployerOwner {
        for (uint256 i; i < _typeIds.length; i++) {
            require(_typeIds[i] < totalTypes, "__updateTypesInfo: Type id is out of range");
            typeToTypeInfo[_typeIds[i]] = TypeInfo({lib: _libs[i], parser: _parsers[i]});
        }
    }

    // PRIVATE FUNCTIONS

    /// @dev Adds new types with new typeInfo structs
    function __addTypesInfo(address[] memory _libs, address[] memory _parsers) private {
        for (uint256 i; i < _libs.length; i++) {
            typeToTypeInfo[totalTypes] = TypeInfo({lib: _libs[i], parser: _parsers[i]});

            totalTypes++;
        }
    }

    /// @dev Creates a new external position and links it to the _vaultProxy.
    function __createExternalPosition(
        address _caller,
        address _vaultProxy,
        bytes memory _callArgs
    ) private {
        (uint256 typeId, bytes memory initArgs) = abi.decode(_callArgs, (uint256, bytes));

        require(typeId < totalTypes, "__createExternalPosition: Invalid typeId");

        IPolicyManager(getPolicyManager()).validatePolicies(
            msg.sender,
            IPolicyManager.PolicyHook.CreateExternalPosition,
            abi.encode(_caller, typeId, initArgs)
        );

        TypeInfo memory typeInfo = getTypeInfo(typeId);

        bytes memory initData = IExternalPositionParser(typeInfo.parser).parseInitArgs(
            _vaultProxy,
            initArgs
        );

        bytes memory constructData = abi.encodeWithSelector(
            IExternalPosition.init.selector,
            initData
        );

        address externalPosition = address(
            new ExternalPositionProxy(constructData, typeInfo.lib, typeId)
        );

        emit ExternalPositionDeployed(msg.sender, _vaultProxy, externalPosition, typeId, initArgs);

        __addExternalPosition(msg.sender, externalPosition);
    }

    // Performs an action on a specific external position, validating the incoming arguments and the final result
    function __executeCallOnExternalPosition(
        address _caller,
        address _vaultProxy,
        bytes memory _callArgs
    ) private {
        (address payable externalPosition, uint256 actionId, bytes memory actionArgs) = abi.decode(
            _callArgs,
            (address, uint256, bytes)
        );

        uint256 typeId = ExternalPositionProxy(externalPosition).getExternalPositionType();

        require(
            IVault(_vaultProxy).isActiveExternalPosition(externalPosition),
            "__executeCallOnExternalPosition: External position is not valid"
        );

        address parser = typeToTypeInfo[typeId].parser;

        (
            address[] memory assetsToTransfer,
            uint256[] memory amountsToTransfer,
            address[] memory assetsToReceive
        ) = IExternalPositionParser(parser).parseAssetsForAction(actionId, actionArgs);

        bytes memory encodedActionData = abi.encode(actionId, actionArgs);

        // Execute callOnExternalPosition
        __callOnExternalPosition(
            msg.sender,
            abi.encode(
                externalPosition,
                encodedActionData,
                assetsToTransfer,
                amountsToTransfer,
                assetsToReceive
            )
        );

        IPolicyManager(getPolicyManager()).validatePolicies(
            msg.sender,
            IPolicyManager.PolicyHook.PostCallOnExternalPosition,
            abi.encode(
                _caller,
                externalPosition,
                assetsToTransfer,
                amountsToTransfer,
                assetsToReceive,
                encodedActionData
            )
        );
    }

    /// @dev Removes an external position from the VaultProxy
    function __executeRemoveExternalPosition(address _caller, bytes memory _callArgs) private {
        address externalPosition = abi.decode(_callArgs, (address));

        IPolicyManager(getPolicyManager()).validatePolicies(
            msg.sender,
            IPolicyManager.PolicyHook.RemoveExternalPosition,
            abi.encode(_caller, externalPosition)
        );

        __removeExternalPosition(msg.sender, externalPosition);
    }

    /// @dev Helper to validate fund owner.
    /// Preferred to a modifier because allows gas savings if re-using _vaultProxy.
    function __validateIsFundOwner(address _vaultProxy, address _who) private view {
        require(
            _who == IVault(_vaultProxy).getOwner(),
            "__validateIsFundOwner: Only the fund owner can call this function"
        );
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `POLICY_MANAGER` variable
    /// @return policyManager_ The `POLICY_MANAGER` variable value
    function getPolicyManager() public view returns (address policyManager_) {
        return POLICY_MANAGER;
    }

    /// @notice Returns the external position type info struct of a given type id
    /// @param _typeId The procotol for which to get the external position's type info
    /// @return typeInfo_ The external position type info struct
    function getTypeInfo(uint256 _typeId) public view returns (TypeInfo memory typeInfo_) {
        return typeToTypeInfo[_typeId];
    }
}
