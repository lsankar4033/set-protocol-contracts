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
        // Address of the Core contract
        address core;

        // Address of the Factory contract
        address factory;

        // Address of the Vault contract
        address vault;

        address componentWhiteListAddress;

        uint256 naturalUnit;
        address manager;
        
        // State updated after every rebalance
        address currentSet;
        uint256 unitShares;
        RebalancingState rebalance;
    }

    struct RebalancingState {
        // State governing rebalance cycle
        uint256 proposalPeriod;
        uint256 rebalanceInterval;

        RebalancingHelperLibrary.State rebalanceState;
        uint256 lastRebalanceTimestamp;
        // State to track proposal period
        uint256 proposalStartTime;

        // State needed for auction/rebalance
        address nextSet;
        address auctionLibrary;
        uint256 startingCurrentSetAmount;

        uint256 auctionStartTime;
        uint256 auctionTimeToPivot;
        uint256 auctionStartPrice;
        uint256 auctionPivotPrice;        
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
        public
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
     * Get auctionParameters of Rebalancing Set
     *
     * @return  auctionParams       Object with auction information
     */
    function getAuctionParameters()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory auctionParams = new uint256[](4);
        auctionParams[0] = state.rebalance.auctionStartTime;
        auctionParams[1] = state.rebalance.auctionTimeToPivot;
        auctionParams[2] = state.rebalance.auctionStartPrice;
        auctionParams[3] = state.rebalance.auctionPivotPrice;
        return auctionParams;
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
}
