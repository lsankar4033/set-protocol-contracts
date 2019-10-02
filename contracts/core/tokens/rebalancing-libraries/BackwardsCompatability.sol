/*
    Copyright 2019 Set Labs Inc.

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

pragma solidity 0.5.7;
pragma experimental "ABIEncoderV2";

import { RebalancingSetState } from "./RebalancingSetState.sol";


/**
 * @title BackwardsCompatability
 * @author Set Protocol
 *
 * Exposes state
 */
contract BackwardsCompatability is 
    RebalancingSetState
{

    /*
     * Get biddingParameters of Rebalancing Set for backwards compatability
     * with the RebalanceAuctionModule
     *
     * @return  biddingParams       Object with bidding information
     */
    function getBiddingParameters()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory biddingParams = new uint256[](2);
        biddingParams[0] = liquidator.minimumBid();
        biddingParams[1] = liquidator.remainingCurrentSets();
        return biddingParams;
    }

    /*
     * Get failedAuctionWithdrawComponents of Rebalancing Set for backwards compatability
     * with the RebalanceAuctionModule
     *
     * @return  failedAuctionWithdrawComponents
     */
    function getFailedAuctionWithdrawComponents()
        external
        view
        returns (address[] memory)
    {
        return failedRebalanceComponents;
    }


}
