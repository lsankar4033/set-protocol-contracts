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
import { ICore } from "../../interfaces/ICore.sol";
import { RebalancingHelperLibrary } from "../../lib/RebalancingHelperLibrary.sol";
import { RebalancingSetState } from "./RebalancingSetState.sol";


/**
 * @title StandardPlaceBidLibrary
 * @author Set Protocol
 *
 * Default implementation of Rebalancing Set Token placeBid function
 */
library StandardPlaceBidLibrary {
    using SafeMath for uint256;

    /* ============ Internal Functions ============ */

    /*
     * Place bid during rebalance auction. Can only be called by Core.
     *
     * @param _quantity                 The amount of currentSet to be rebalanced
     * @param _auctionParameters        Struct containing auction price curve parameters
     * @return inflowUnitArray          Array of amount of tokens inserted into system in bid
     * @return outflowUnitArray         Array of amount of tokens taken out of system in bid
     */
    function placeBid(
        uint256 _quantity,
        RebalancingHelperLibrary.AuctionPriceParameters memory _auctionParameters,
        RebalancingSetState.State storage _state
    )
        internal
        view
        returns (uint256[] memory, uint256[] memory)
    {
        // Make sure sender is a module
        require(
            ICore(_state.core).validModules(msg.sender),
            "RebalancingSetToken.placeBid: Sender must be approved module"
        );

        // Make sure that bid amount is multiple of minimum bid amount
        require(
            _quantity % _state.bidding.minimumBid == 0,
            "RebalancingSetToken.placeBid: Must bid multiple of minimum bid"
        );

        // Make sure that bid Amount is less than remainingCurrentSets
        require(
            _quantity <= _state.bidding.remainingCurrentSets,
            "RebalancingSetToken.placeBid: Bid exceeds remaining current sets"
        );

        return RebalancingHelperLibrary.getBidPrice(
            _quantity,
            _state.rebalance.auctionLibrary,
            _state.bidding,
            _auctionParameters,
            uint8(_state.rebalance.rebalanceState)
        );
    }
}
