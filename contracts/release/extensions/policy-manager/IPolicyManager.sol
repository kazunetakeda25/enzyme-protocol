// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Council <council@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

/// @title PolicyManager Interface
/// @author Enzyme Council <security@enzyme.finance>
/// @notice Interface for the PolicyManager
interface IPolicyManager {
    // When updating PolicyHook, also update these functions in PolicyManager:
    // 1. __getAllPolicyHooks()
    // 2. __policyHookRestrictsCurrentInvestorActions()
    enum PolicyHook {
        PostBuyShares,
        PostCallOnIntegration,
        PreTransferShares,
        RedeemSharesForSpecificAssets,
        AddTrackedAssets,
        RemoveTrackedAssets,
        CreateExternalPosition,
        PostCallOnExternalPosition,
        RemoveExternalPosition,
        ReactivateExternalPosition
    }

    function disablePolicyForFund(address _comptrollerProxy, address _policy) external;

    function enablePolicyForFund(address _comptrollerProxy, address _policy, bytes calldata _settingsData) external;

    function updatePolicySettingsForFund(address _comptrollerProxy, address _policy, bytes calldata _settingsData)
        external;

    function validatePolicies(address, PolicyHook, bytes calldata) external;
}
