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
import { CommonMath } from "../../lib/CommonMath.sol";
import { ERC20Wrapper } from "../../lib/ERC20Wrapper.sol";
import { ICore } from "../interfaces/ICore.sol";
import { IRebalancingSetFactory } from "../interfaces/IRebalancingSetFactory.sol";
import { ISetToken } from "../interfaces/ISetToken.sol";
import { IVault } from "../interfaces/IVault.sol";
import { IWhiteList } from "../interfaces/IWhiteList.sol";
import { RebalancingHelperLibrary } from "../lib/RebalancingHelperLibrary.sol";
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

    /* ============ State Variables ============ */

    StandardStartRebalanceLibrary.BiddingParameters public biddingParameters;

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

        state.core = IRebalancingSetFactory(_factory).core();
        state.vault = ICore(state.core).vault();
        state.componentWhiteListAddress = _componentWhiteList;
        state.factory = _factory;
        state.manager = _manager;
        state.currentSet = _initialSet;
        state.unitShares = _initialUnitShares;
        state.naturalUnit = _naturalUnit;

        rebalancingState.proposalPeriod = _proposalPeriod;
        rebalancingState.rebalanceInterval = _rebalanceInterval;
        rebalancingState.lastRebalanceTimestamp = block.timestamp;
        rebalancingState.rebalanceState = RebalancingHelperLibrary.State.Default;
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
        // Validate proposal inputs and initialize auctionParameters
        RebalancingHelperLibrary.AuctionPriceParameters memory auctionParameters = StandardProposeLibrary.propose(
            _nextSet,
            _auctionLibrary,
            _auctionTimeToPivot,
            _auctionStartPrice,
            _auctionPivotPrice,
            rebalancingState,
            state
        );

        rebalancingState.auctionStartTime = auctionParameters.auctionStartTime;
        rebalancingState.auctionTimeToPivot = auctionParameters.auctionTimeToPivot;
        rebalancingState.auctionStartPrice = auctionParameters.auctionStartPrice;
        rebalancingState.auctionPivotPrice = auctionParameters.auctionPivotPrice;

        // Update state parameters
        rebalancingState.nextSet = _nextSet;
        rebalancingState.auctionLibrary = _auctionLibrary;
        rebalancingState.proposalStartTime = block.timestamp;
        rebalancingState.rebalanceState = RebalancingHelperLibrary.State.Proposal;

        emit RebalanceProposed(
            _nextSet,
            _auctionLibrary,
            rebalancingState.proposalStartTime.add(rebalancingState.proposalPeriod)
        );
    }

    /*
     * Initiate rebalance for the rebalancing set. Users can now submit bids.
     *
     */
    function startRebalance()
        external
    {
        // Redeem currentSet and define biddingParameters
        biddingParameters = StandardStartRebalanceLibrary.startRebalance(
            state.currentSet,
            rebalancingState.nextSet,
            rebalancingState.auctionLibrary,
            state.core,
            state.vault,
            rebalancingState.proposalStartTime,
            rebalancingState.proposalPeriod,
            uint8(rebalancingState.rebalanceState)
        );

        // Update state parameters
        rebalancingState.startingCurrentSetAmount = biddingParameters.remainingCurrentSets;
        rebalancingState.auctionStartTime = block.timestamp;
        rebalancingState.rebalanceState = RebalancingHelperLibrary.State.Rebalance;

        emit RebalanceStarted(state.currentSet, rebalancingState.nextSet);
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
            biddingParameters.remainingCurrentSets,
            biddingParameters.minimumBid,
            state.naturalUnit,
            rebalancingState.nextSet,
            state.core,
            state.vault,
            uint8(rebalancingState.rebalanceState)
        );

        // Update other state parameters
        state.currentSet = rebalancingState.nextSet;
        rebalancingState.lastRebalanceTimestamp = block.timestamp;
        rebalancingState.rebalanceState = RebalancingHelperLibrary.State.Default;
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
            rebalancingState.auctionLibrary,
            state.core,
            biddingParameters,
            auctionParameters(),
            uint8(rebalancingState.rebalanceState)
        );

        // Update remaining Set figure to transact
        biddingParameters.remainingCurrentSets = biddingParameters.remainingCurrentSets.sub(_quantity);

        return (biddingParameters.combinedTokenArray, inflowUnitArray, outflowUnitArray);
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
            state.naturalUnit,
            rebalancingState.nextSet,
            state.vault
        );

        // Fail auction and either reset to Default state or kill Rebalancing Set Token and enter Drawdown
        // state
        uint8 integerRebalanceState = StandardFailAuctionLibrary.endFailedAuction(
            rebalancingState.startingCurrentSetAmount,
            calculatedUnitShares,
            state.currentSet,
            state.core,
            auctionParameters(),
            biddingParameters,
            uint8(rebalancingState.rebalanceState)
        );
        rebalancingState.rebalanceState = RebalancingHelperLibrary.State(integerRebalanceState);

        // Reset lastRebalanceTimestamp to now
        rebalancingState.lastRebalanceTimestamp = block.timestamp;
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
            rebalancingState.auctionLibrary,
            biddingParameters,
            auctionParameters(),
            uint8(rebalancingState.rebalanceState)
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
        // Check that function caller is Core
        require(
            msg.sender == state.core,
            "RebalancingSetToken.mint: Sender must be core"
        );

        // Check that set is not in Rebalance State
        require(
            rebalancingState.rebalanceState != RebalancingHelperLibrary.State.Rebalance,
            "RebalancingSetToken.mint: Cannot mint during Rebalance"
        );

        // Check that set is not in Drawdown State
        require(
            rebalancingState.rebalanceState != RebalancingHelperLibrary.State.Drawdown,
            "RebalancingSetToken.mint: Cannot mint during Drawdown"
        );

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
        // Check that set is not in Rebalancing State
        require(
            rebalancingState.rebalanceState != RebalancingHelperLibrary.State.Rebalance,
            "RebalancingSetToken.burn: Cannot burn during Rebalance"
        );

        // Check to see if state is Drawdown
        if (rebalancingState.rebalanceState == RebalancingHelperLibrary.State.Drawdown) {
            // In Drawdown Sets can only be burned as part of the withdrawal process
            require(
                ICore(state.core).validModules(msg.sender),
                "RebalancingSetToken.burn: Set cannot be redeemed during Drawdown"
            );
        } else {
            // When in non-Rebalance or Drawdown state, check that function caller is Core
            // so that Sets can be redeemed
            require(
                msg.sender == state.core,
                "RebalancingSetToken.burn: Sender must be core"
            );
        }

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

    /* ============ Public Getters ============ */

    /*
     * Get biddingParameters of Rebalancing Set
     *
     * @return  biddingParams       Object with bidding information
     */
    function getBiddingParameters()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory biddingParams = new uint256[](2);
        biddingParams[0] = biddingParameters.minimumBid;
        biddingParams[1] = biddingParameters.remainingCurrentSets;
        return biddingParams;
    }

    /*
     * Get combinedTokenArray of Rebalancing Set
     *
     * @return  combinedTokenArray
     */
    function getCombinedTokenArrayLength()
        external
        view
        returns (uint256)
    {
        return biddingParameters.combinedTokenArray.length;
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
        return biddingParameters.combinedTokenArray;
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
        return biddingParameters.combinedCurrentUnits;
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
        return biddingParameters.combinedNextSetUnits;
    }
}
