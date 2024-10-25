// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import "./RetroFund.sol";

/**
 * @title RetroFundSetup
 * @dev Setup contract for RetroFund plugin installation
 */
contract RetroFundSetup is PluginSetup {
    address public immutable implementation;

    constructor() {
        implementation = address(new RetroFund());
    }

    function prepareInstallation(
        address _dao,
        bytes memory _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Create plugin proxy
        plugin = createERC1967Proxy(
            implementation,
            abi.encodeWithSelector(
                RetroFund.initialize.selector,
                _dao
            )
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](4);

        // Grant permissions
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            RetroFund(plugin).TRUSTED_COMMITTEE_ROLE(),
            _dao
        );

        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            RetroFund(plugin).SUBMIT_PROPOSAL_ROLE(),
            _dao
        );

        permissions[2] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            RetroFund(plugin).VOTE_ROLE(),
            _dao
        );

        permissions[3] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            RetroFund(plugin).RELEASE_ROLE(),
            _dao
        );

        preparedSetupData.permissions = permissions;
    }

    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](4);

        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            keccak256("TRUSTED_COMMITTEE_ROLE"),
            _dao
        );

        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            keccak256("SUBMIT_PROPOSAL_ROLE"),
            _dao
        );

        permissions[2] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            keccak256("VOTE_ROLE"),
            _dao
        );

        permissions[3] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            keccak256("RELEASE_ROLE"),
            _dao
        );
    }
}