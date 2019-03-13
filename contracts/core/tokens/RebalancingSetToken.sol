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

import { ERC20 } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { ERC20Detailed } from "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import { Math } from "openzeppelin-solidity/contracts/math/Math.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { AddressArrayUtils } from "../../lib/AddressArrayUtils.sol";
import { Bytes32 } from "../../lib/Bytes32.sol";
import { ERC20Wrapper } from "../../lib/ERC20Wrapper.sol";
import { ICore } from "../interfaces/ICore.sol";
import { IRebalancingSetFactory } from "../interfaces/IRebalancingSetFactory.sol";
import { ISetToken } from "../interfaces/ISetToken.sol";
import { RebalancingHelperLibrary } from "../lib/RebalancingHelperLibrary.sol";
import { RebalancingSetLibrary } from "./rebalancing-libraries/RebalancingSetLibrary.sol";
import { RebalancingSetState } from "./rebalancing-libraries/RebalancingSetState.sol";
import { StandardFailAuctionLibrary } from "./rebalancing-libraries/StandardFailAuctionLibrary.sol";
import { StandardPlaceBidLibrary } from "./rebalancing-libraries/StandardPlaceBidLibrary.sol";
import { StandardProposeLibrary } from "./rebalancing-libraries/StandardProposeLibrary.sol";
import { StandardSettleRebalanceLibrary } from "./rebalancing-libraries/StandardSettleRebalanceLibrary.sol";
import { StandardStartRebalanceLibrary } from "./rebalancing-libraries/StandardStartRebalanceLibrary.sol";


/**
 * @title RebalancingSetToken
 * @author Set Protocol
 *
 * Implementation of Rebalancing Set token.
 */
contract RebalancingSetToken is
    ERC20,
    ERC20Detailed,
    RebalancingSetState
{
    using SafeMath for uint256;
    using Bytes32 for bytes32;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */

    event NewManagerAdded(
        address newManager,
        address oldManager
    );

    event RebalanceProposed(
        address nextSet,
        address indexed auctionLibrary,
        uint256 indexed proposalPeriodEndTime
    );

    event RebalanceStarted(
        address oldSet,
        address newSet
    );

    /* ============ Constructor ============ */

    /**
     * Constructor function for Rebalancing Set Token
     *
     * @param _factory                   Factory used to create the Rebalancing Set
     * @param _manager                   Manager of the Rebalancing Set
     * @param _initialSet                Initial set that collateralizes the Rebalancing set
     * @param _initialUnitShares         Units of currentSet that equals one share
     * @param _naturalUnit               The minimum multiple of Sets that can be issued or redeemed
     * @param _proposalPeriod            Amount of time for users to inspect a rebalance proposal
     * @param _rebalanceInterval         Minimum amount of time between rebalances
     * @param _componentWhiteList        Address of component WhiteList contract
     * @param _name                      The name of the new RebalancingSetToken
     * @param _symbol                    The symbol of the new RebalancingSetToken
     */

    constructor(
        address _factory,
        address _manager,
        address _initialSet,
        uint256 _initialUnitShares,
        uint256 _naturalUnit,
        uint256 _proposalPeriod,
        uint256 _rebalanceInterval,
        address _componentWhiteList,
        string memory _name,
        string memory _symbol
    )
        public
        ERC20Detailed(
            _name,
            _symbol,
            18
        )
    {
        state.core = IRebalancingSetFactory(_factory).core();
        state.vault = ICore(state.core).vault();
        state.componentWhiteListAddress = _componentWhiteList;
        state.factory = _factory;
        state.manager = _manager;
        state.currentSet = _initialSet;
        state.unitShares = _initialUnitShares;
        state.naturalUnit = _naturalUnit;

        state.rebalance.proposalPeriod = _proposalPeriod;
        state.rebalance.rebalanceInterval = _rebalanceInterval;
        state.rebalance.lastRebalanceTimestamp = block.timestamp;
        state.rebalance.rebalanceState = RebalancingHelperLibrary.State.Default;
    }

    /* ============ Public Functions ============ */

    /**
     * Function used to set the terms of the next rebalance and start the proposal period
     *
     * @param _nextSet                      The Set to rebalance into
     * @param _auctionLibrary               The library used to calculate the Dutch Auction price
     * @param _auctionTimeToPivot           The amount of time for the auction to go ffrom start to pivot price
     * @param _auctionStartPrice            The price to start the auction at
     * @param _auctionPivotPrice            The price at which the price curve switches from linear to exponential
     */
    function propose(
        address _nextSet,
        address _auctionLibrary,
        uint256 _auctionTimeToPivot,
        uint256 _auctionStartPrice,
        uint256 _auctionPivotPrice
    )
        external
    {
        uint256 auctionStartTime = StandardProposeLibrary.getAuctionStartTime();

        // Validate proposal inputs and initialize getAuctionParameters
        StandardProposeLibrary.validateProposalParams(
            _nextSet,
            _auctionLibrary,
            auctionStartTime,
            _auctionTimeToPivot,
            _auctionStartPrice,
            _auctionPivotPrice,
            state
        );

        // Update state parameters
        state = StandardProposeLibrary.updateState(
            _nextSet,
            _auctionLibrary,
            auctionStartTime,
            _auctionTimeToPivot,
            _auctionStartPrice,
            _auctionPivotPrice,
            state
        );
        emit RebalanceProposed(
            _nextSet,
            _auctionLibrary,
            state.rebalance.proposalStartTime.add(state.rebalance.proposalPeriod)
        );
    }

    /*
     * Initiate rebalance for the rebalancing set. Users can now submit bids.
     *
     */
    function startRebalance()
        external
    {
        // Redeem currentSet and define state.bidding
        state.bidding = StandardStartRebalanceLibrary.startRebalance(state);

        // Update state parameters
        state = StandardStartRebalanceLibrary.updateState(state);

        emit RebalanceStarted(state.currentSet, state.rebalance.nextSet);
    }

    /*
     * Initiate settlement for the rebalancing set. Full functionality now returned to
     * set owners
     *
     */
    function settleRebalance()
        external
    {
        // Settle the rebalance and mint next Sets
        state.unitShares = StandardSettleRebalanceLibrary.settleRebalance(
            totalSupply(),
            state
        );

        // Update other state parameters
        state.currentSet = state.rebalance.nextSet;
        state.rebalance.lastRebalanceTimestamp = block.timestamp;
        state.rebalance.rebalanceState = RebalancingHelperLibrary.State.Default;
    }

    /*
     * Place bid during rebalance auction. Can only be called by Core.
     *
     * @param _quantity                 The amount of currentSet to be rebalanced
     * @return combinedTokenArray       Array of token addresses invovled in rebalancing
     * @return inflowUnitArray          Array of amount of tokens inserted into system in bid
     * @return outflowUnitArray         Array of amount of tokens taken out of system in bid
     */
    function placeBid(
        uint256 _quantity
    )
        external
        returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        // Place bid and get back inflow and outflow arrays
        uint256[] memory inflowUnitArray;
        uint256[] memory outflowUnitArray;
        (
            inflowUnitArray,
            outflowUnitArray
        ) = StandardPlaceBidLibrary.placeBid(
            _quantity,
            getAuctionParameters(),
            state
        );

        // Update remaining Set figure to transact
        state.bidding.remainingCurrentSets = state.bidding.remainingCurrentSets.sub(_quantity);

        return (state.bidding.combinedTokenArray, inflowUnitArray, outflowUnitArray);
    }

    /*
     * Fail an auction that doesn't complete before reaching the pivot price. Move to Drawdown state
     * if bids have been placed. Reset to Default state if no bids placed.
     *
     */
    function endFailedAuction()
        external
    {
        uint256 calculatedUnitShares;
        (
            ,
            calculatedUnitShares
        ) = StandardSettleRebalanceLibrary.calculateNextSetIssueQuantity(
            totalSupply(),
            state
        );

        // Fail auction and either reset to Default state or kill Rebalancing Set Token and enter Drawdown
        // state
        uint8 integerRebalanceState = StandardFailAuctionLibrary.endFailedAuction(
            state.rebalance.startingCurrentSetAmount,
            calculatedUnitShares,
            getAuctionParameters(),
            state
        );
        state.rebalance.rebalanceState = RebalancingHelperLibrary.State(integerRebalanceState);

        // Reset lastRebalanceTimestamp to now
        state.rebalance.lastRebalanceTimestamp = block.timestamp;
    }

    /*
     * Get token inflows and outflows required for bid. Also the amount of Rebalancing
     * Sets that would be generated.
     *
     * @param _quantity               The amount of currentSet to be rebalanced
     * @return inflowUnitArray        Array of amount of tokens inserted into system in bid
     * @return outflowUnitArray       Array of amount of tokens taken out of system in bid
     */
    function getBidPrice(
        uint256 _quantity
    )
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        return RebalancingHelperLibrary.getBidPrice(
            _quantity,
            state.rebalance.auctionLibrary,
            state.bidding,
            getAuctionParameters(),
            uint8(state.rebalance.rebalanceState)
        );
    }

    /*
     * Mint set token for given address.
     * Can only be called by Core contract.
     *
     * @param  _issuer      The address of the issuing account
     * @param  _quantity    The number of sets to attribute to issuer
     */
    function mint(
        address _issuer,
        uint256 _quantity
    )
        external
    {
        // RebalancingSetLibrary.validateMint(state);

        // Update token balance of the manager
        _mint(_issuer, _quantity);
    }

    /*
     * Burn set token for given address.
     * Can only be called by authorized contracts.
     *
     * @param  _from        The address of the redeeming account
     * @param  _quantity    The number of sets to burn from redeemer
     */
    function burn(
        address _from,
        uint256 _quantity
    )
        external
    {
        // RebalancingSetLibrary.validateBurn(state);

        _burn(_from, _quantity);
    }

    /*
     * Set new manager address
     *
     * @param  _newManager       The address of the new manager account
     */
    function setManager(
        address _newManager
    )
        external
    {
        require(
            msg.sender == state.manager,
            "RebalancingSetToken.setManager: Sender must be the manager"
        );

        emit NewManagerAdded(_newManager, state.manager);
        state.manager = _newManager;
    }
}
