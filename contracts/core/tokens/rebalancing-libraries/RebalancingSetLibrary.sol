/*
    Copyright 2018 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

pragma solidity 0.5.4;
pragma experimental "ABIEncoderV2";

import { ICore } from "../../interfaces/ICore.sol";
import { IRebalancingSetFactory } from "../../interfaces/IRebalancingSetFactory.sol";
import { RebalancingHelperLibrary } from "../../lib/RebalancingHelperLibrary.sol";
import { RebalancingSetState } from "./RebalancingSetState.sol";


/**
 * @title RebalancingSetLibrary
 * @author Set Protocol
 *
 * xxx
 */
library RebalancingSetLibrary {
    function validateConstructor(
        address _factory,
        address _manager,
        uint256 _initialUnitShares,
        uint256 _naturalUnit,
        uint256 _proposalPeriod,
        uint256 _rebalanceInterval
    )
        internal
    {
           // Require initial unit shares is non-zero
        require(
            _initialUnitShares > 0,
            "RebalancingSetToken.constructor: Unit shares must be positive"
        );

        IRebalancingSetFactory tokenFactory = IRebalancingSetFactory(_factory);

        require(
            _naturalUnit >= tokenFactory.minimumNaturalUnit(),
            "RebalancingSetToken.constructor: Natural Unit too low"
        );

        require(
            _naturalUnit <= tokenFactory.maximumNaturalUnit(),
            "RebalancingSetToken.constructor: Natural Unit too large"
        );

        // Require manager address is non-zero
        require(
            _manager != address(0),
            "RebalancingSetToken.constructor: Invalid manager address"
        );

        // Require minimum rebalance interval and proposal period from factory
        require(
            _proposalPeriod >= tokenFactory.minimumProposalPeriod(),
            "RebalancingSetToken.constructor: Proposal period too short"
        );
        require(
            _rebalanceInterval >= tokenFactory.minimumRebalanceInterval(),
            "RebalancingSetToken.constructor: Rebalance interval too short"
        );
    }

    function validateMint(
        RebalancingSetState.State storage _state
    )
        internal
        view
    {
        // Check that function caller is Core
        require(
            msg.sender == _state.core,
            "RebalancingSetToken.mint: Sender must be core"
        );

        // Check that set is not in Rebalance State
        require(
            _state.rebalance.rebalanceState != RebalancingHelperLibrary.State.Rebalance,
            "RebalancingSetToken.mint: Cannot mint during Rebalance"
        );

        // Check that set is not in Drawdown State
        require(
            _state.rebalance.rebalanceState != RebalancingHelperLibrary.State.Drawdown,
            "RebalancingSetToken.mint: Cannot mint during Drawdown"
        );
    }

    function validateBurn(
        RebalancingSetState.State storage _state
    )
        internal
        view
    {
        // Check that set is not in Rebalancing State
        require(
            _state.rebalance.rebalanceState != RebalancingHelperLibrary.State.Rebalance,
            "RebalancingSetToken.burn: Cannot burn during Rebalance"
        );

        // Check to see if state is Drawdown
        if (_state.rebalance.rebalanceState == RebalancingHelperLibrary.State.Drawdown) {
            // In Drawdown Sets can only be burned as part of the withdrawal process
            require(
                ICore(_state.core).validModules(msg.sender),
                "RebalancingSetToken.burn: Set cannot be redeemed during Drawdown"
            );
        } else {
            // When in non-Rebalance or Drawdown state, check that function caller is Core
            // so that Sets can be redeemed
            require(
                msg.sender == _state.core,
                "RebalancingSetToken.burn: Sender must be core"
            );
        }        
    }


}
