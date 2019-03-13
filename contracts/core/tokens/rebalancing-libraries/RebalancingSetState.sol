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
import { ISetToken } from "../../interfaces/ISetToken.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { IWhiteList } from "../../interfaces/IWhiteList.sol";
import { RebalancingHelperLibrary } from "../../lib/RebalancingHelperLibrary.sol";
import { StandardStartRebalanceLibrary } from "./StandardStartRebalanceLibrary.sol";


/**
 * @title RebalancingSetState
 * @author Set Protocol
 *
 * The RebalancingSetState library maintains all state for the Core contract thus
 * allowing it to operate across multiple mixins.
 */
contract RebalancingSetState {

    /* ============ Structs ============ */

    struct State {
        address core;
        address factory;
        address vault;
        address componentWhiteListAddress;
        address manager;
        address currentSet;

        uint256 unitShares;
        uint256 naturalUnit;

        RebalancingState rebalance;
        BiddingState bidding;
    }

    // State needed for auction/rebalance
    struct RebalancingState {
        address nextSet;
        address auctionLibrary;

        RebalancingHelperLibrary.State rebalanceState;

        // State governing rebalance cycle
        uint256 proposalPeriod;
        uint256 rebalanceInterval;
        uint256 lastRebalanceTimestamp;
        uint256 proposalStartTime;
        uint256 startingCurrentSetAmount;
        uint256 auctionStartTime;
        uint256 auctionTimeToPivot;
        uint256 auctionStartPrice;
        uint256 auctionPivotPrice;        
    }

    struct BiddingState {
        uint256 minimumBid;
        uint256 remainingCurrentSets;
        uint256[] combinedCurrentUnits;
        uint256[] combinedNextSetUnits;
        address[] combinedTokenArray;
    }

    /* ============ State Variables ============ */

    State public state;

    /* ============ Public Getters ============ */

    function core()
        external
        view
        returns(address)
    {
        return state.core;
    }

    function factory()
        external
        view
        returns(address)
    {
        return state.factory;
    }

    function vault()
        external
        view
        returns(address)
    {
        return state.vault;
    }

    function naturalUnit()
        external
        view
        returns(uint256)
    {
        return state.naturalUnit;
    }

    function manager()
        external
        view
        returns(address)
    {
        return state.manager;
    }

    function rebalanceState()
        external
        view
        returns(uint8)
    {
        return uint8(state.rebalance.rebalanceState);
    }

    function currentSet()
        external
        view
        returns(address)
    {
        return state.currentSet;
    }

    function unitShares()
        external
        view
        returns(uint256)
    {
        return state.unitShares;
    }

    function proposalPeriod()
        external
        view
        returns(uint256)
    {
        return state.rebalance.proposalPeriod;
    }

    function rebalanceInterval()
        external
        view
        returns(uint256)
    {
        return state.rebalance.rebalanceInterval;
    }

    function lastRebalanceTimestamp()
        external
        view
        returns(uint256)
    {
        return state.rebalance.lastRebalanceTimestamp;
    }

    function proposalStartTime()
        external
        view
        returns(uint256)
    {
        return state.rebalance.proposalStartTime;
    }

    function nextSet()
        external
        view
        returns(address)
    {
        return state.rebalance.nextSet;
    }

    function auctionLibrary()
        external
        view
        returns(address)
    {
        return state.rebalance.auctionLibrary;
    }

    function startingCurrentSetAmount()
        external
        view
        returns(uint256)
    {
        return state.rebalance.startingCurrentSetAmount;
    }

    /*
     * Get addresses of setToken underlying the Rebalancing Set
     *
     * @return  componentAddresses       Array of currentSet
     */
    function getComponents()
        external
        view
        returns (address[] memory)
    {
        address[] memory components = new address[](1);
        components[0] = state.currentSet;
        return components;
    }

    /*
     * Get unitShares of Rebalancing Set
     *
     * @return  units       Array of component unit
     */
    function getUnits()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory units = new uint256[](1);
        units[0] = state.unitShares;
        return units;
    }

    function auctionParameters()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory auctionParameters = new uint256[](4);
        auctionParameters[0] = state.rebalance.auctionStartTime;
        auctionParameters[1] = state.rebalance.auctionTimeToPivot;
        auctionParameters[2] = state.rebalance.auctionStartPrice;
        auctionParameters[3] = state.rebalance.auctionPivotPrice;
        return auctionParameters;
    }

    /*
     * Get auctionParameters of Rebalancing Set
     *
     * @return  auctionParams       Object with auction information
     */
    function getAuctionParameters()
        internal
        view
        returns (RebalancingHelperLibrary.AuctionPriceParameters memory)
    {
        return RebalancingHelperLibrary.AuctionPriceParameters({
            auctionStartTime: state.rebalance.auctionStartTime,
            auctionTimeToPivot: state.rebalance.auctionTimeToPivot,
            auctionStartPrice: state.rebalance.auctionStartPrice,
            auctionPivotPrice: state.rebalance.auctionPivotPrice
        });
    }

    /*
     * Checks to make sure address is the current set of the RebalancingSetToken.
     * Conforms to the ISetToken Interface.
     *
     * @param  _tokenAddress     Address of token being checked
     * @return  bool             True if token is the current Set
     */
    function tokenIsComponent(
        address _tokenAddress
    )
        external
        view
        returns (bool)
    {
        return _tokenAddress == state.currentSet;
    }

    /*
     * Get state.bidding of Rebalancing Set
     *
     * @return  biddingParams       Object with bidding information
     */
    function biddingParameters()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory biddingParams = new uint256[](2);
        biddingParams[0] = state.bidding.minimumBid;
        biddingParams[1] = state.bidding.remainingCurrentSets;
        return biddingParams;
    }

    /*
     * Get combinedTokenArray of Rebalancing Set
     *
     * @return  combinedTokenArray
     */
    function getCombinedTokenArray()
        external
        view
        returns (address[] memory)
    {
        return state.bidding.combinedTokenArray;
    }

    /*
     * Get combinedCurrentUnits of Rebalancing Set
     *
     * @return  combinedCurrentUnits
     */
    function getCombinedCurrentUnits()
        external
        view
        returns (uint256[] memory)
    {
        return state.bidding.combinedCurrentUnits;
    }

    /*
     * Get combinedNextSetUnits of Rebalancing Set
     *
     * @return  combinedNextSetUnits
     */
    function getCombinedNextSetUnits()
        external
        view
        returns (uint256[] memory)
    {
        return state.bidding.combinedNextSetUnits;
    }
}
