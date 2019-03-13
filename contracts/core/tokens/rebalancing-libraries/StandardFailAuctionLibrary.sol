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

import { Math } from "openzeppelin-solidity/contracts/math/Math.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { CommonMath } from "../../../lib/CommonMath.sol";
import { ICore } from "../../interfaces/ICore.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { ISetToken } from "../../interfaces/ISetToken.sol";
import { RebalancingHelperLibrary } from "../../lib/RebalancingHelperLibrary.sol";
import { RebalancingSetState } from "./RebalancingSetState.sol";


/**
 * @title StandardFailAuctionLibrary
 * @author Set Protocol
 *
 * Default implementation of Rebalancing Set Token endFailedAuction function
 */
library StandardFailAuctionLibrary {
    using SafeMath for uint256;

    /**
     * Fail an auction that doesn't complete before reaching the pivot price. Move to Drawdown state
     * if bids have been placed. Reset to Default state if no bids placed.
     *
     * @param _startingCurrentSetAmount     Amount of current set at beginning or rebalance
     * @param _calculatedUnitShares         Calculated unitShares amount if rebalance were to be settled
     * @param _auctionParameters            Struct containing auction price curve parameters
     * @return                              State of Rebalancing Set after function called
     */
    function endFailedAuction(
        uint256 _startingCurrentSetAmount,
        uint256 _calculatedUnitShares,
        RebalancingHelperLibrary.AuctionPriceParameters memory _auctionParameters,
        RebalancingSetState.State storage _state
    )
        internal
        returns (uint8)
    {
        // Token must be in Rebalance State
        require(
            uint8(_state.rebalance.rebalanceState) ==  uint8(RebalancingHelperLibrary.State.Rebalance),
            "RebalanceAuctionModule.endFailedAuction: Rebalancing Set Token must be in Rebalance State"
        );

        // Calculate timestamp when pivot is reached
        uint256 revertAuctionTime = _auctionParameters.auctionStartTime.add(
            _auctionParameters.auctionTimeToPivot
        );

        // Make sure auction has gone past pivot point
        require(
            block.timestamp >= revertAuctionTime,
            "RebalanceAuctionModule.endFailedAuction: Can only be called after auction reaches pivot"
        );

        uint8 newRebalanceState;
        /**
         * If not enough sets have been bid on then allow auction to fail where no bids being registered
         * returns the rebalancing set token to pre-auction state and some bids being registered puts the
         * rebalancing set token in Drawdown mode.
         *
         * However, if enough sets have been bid on. Then allow auction to fail and enter Drawdown state if
         * and only if the calculated post-auction unitShares is equal to 0.
         */
        if (_state.bidding.remainingCurrentSets >= _state.bidding.minimumBid) {
            // Check if any bids have been placed
            if (_startingCurrentSetAmount == _state.bidding.remainingCurrentSets) {
                // If bid not placed, reissue current Set
                ICore(_state.core).issueInVault(
                    _state.currentSet,
                    _startingCurrentSetAmount
                );

                // Set Rebalance Set Token state to Default
                newRebalanceState = uint8(RebalancingHelperLibrary.State.Default);
            } else {
                // Set Rebalancing Set Token to Drawdown state
                newRebalanceState = uint8(RebalancingHelperLibrary.State.Drawdown);
            }
        } else {
            // If settleRebalance can be called then endFailedAuction can't be
            require(
                _calculatedUnitShares == 0,
                "RebalancingSetToken.endFailedAuction: Cannot be called if rebalance is viably completed"
            );

            // If calculated unitShares equals 0 set to Drawdown state
            newRebalanceState = uint8(RebalancingHelperLibrary.State.Drawdown);
        }

        return newRebalanceState;
    }
}
