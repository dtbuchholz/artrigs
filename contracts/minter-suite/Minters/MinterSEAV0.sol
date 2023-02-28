// SPDX-License-Identifier: LGPL-3.0-only
// Created By: Art Blocks Inc.

import {IWETH} from "../../interfaces/0.8.x/IWETH.sol";

import "../../interfaces/0.8.x/IGenArt721CoreContractV3_Base.sol";
import "../../interfaces/0.8.x/IMinterFilterV0.sol";
import "../../interfaces/0.8.x/IMinterSEAV0.sol";
import "./MinterBase_v0_1_1.sol";

import "@openzeppelin-4.5/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin-4.5/contracts/utils/math/SafeCast.sol";

pragma solidity 0.8.17;

/**
 * @title Filtered Minter contract that allows tokens to be minted with ETH.
 * Pricing is achieved using an automated serial English Auction mechanism.
 * This is designed to be used with GenArt721CoreContractV3 flagship or
 * engine contracts.
 * @author Art Blocks Inc.
 * @notice This contract was inspired by the release mechanism implemented by
 * nouns.wtf, and we thank them for their pioneering work in this area.
 /*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************
 * @notice Privileged Roles and Ownership:
 * This contract is designed to be managed, with limited powers.
 * Privileged roles and abilities are controlled by the core contract's Admin
 * ACL contract and a project's artist. Both of these roles hold extensive
 * power and can modify minter details.
 * Care must be taken to ensure that the admin ACL contract and artist
 * addresses are secure behind a multi-sig or other access control mechanism.
 * ----------------------------------------------------------------------------
 * The following functions are restricted to the core contract's Admin ACL
 * contract:
 * - TODO
 * ----------------------------------------------------------------------------
 * The following functions are restricted to a project's artist:
 * - TODO
 * - setProjectMaxInvocations
 * - manuallyLimitProjectMaxInvocations
 * ----------------------------------------------------------------------------
 * Additional admin and artist privileged roles may be described on other
 * contracts that this minter integrates with.
 *
 * @dev Note that while this minter makes use of `block.timestamp` and it is
 * technically possible that this value is manipulated by block producers, such
 * manipulation will not have material impact on the price values of this minter
 * given the business practices for how pricing is congfigured for this minter
 * and that variations on the order of less than a minute should not
 * meaningfully impact price given the minimum allowable price decay rate that
 * this minter intends to support.
 */
contract MinterSEAV0 is ReentrancyGuard, MinterBase, IMinterSEAV0 {
    using SafeCast for uint256;

    /// Core contract address this minter interacts with
    address public immutable genArt721CoreAddress;

    /// The core contract integrates with V3 contracts
    IGenArt721CoreContractV3_Base private immutable genArtCoreContract_Base;

    /// Minter filter address this minter interacts with
    address public immutable minterFilterAddress;

    /// Minter filter this minter may interact with.
    IMinterFilterV0 private immutable minterFilter;

    /// minterType for this minter
    string public constant minterType = "MinterSEAV0";

    /// minter version for this minter
    string public constant minterVersion = "v0.0.0";

    /// The public WETH contract address
    /// @dev WETH is used as fallback payment method when ETH transfers are
    /// failing during bidding process (e.g. receive function is not payable)
    IWETH public immutable weth;

    uint256 constant ONE_MILLION = 1_000_000;

    // project-specific parameters
    struct ProjectConfig {
        bool maxHasBeenInvoked;
        // max uint24 ~= 1.6e7, > max possible project invocations of 1e6
        uint24 maxInvocations;
        // time after which new auctions may be started
        // note: new auctions must always be started with a new bid, at which
        // point the auction will actually start
        // @dev this is a project-level constraint, and individual auctions
        // will each have their own start time defined in `activeAuction`
        // max uint64 ~= 1.8e19 sec ~= 570 billion years
        uint64 timestampStart;
        // duration of each new auction, before any extensions due to late bids
        uint32 auctionDurationSeconds;
        // reserve price, i.e. minimum starting bid price, in wei
        uint256 basePrice;
        // active auction for project
        Auction activeAuction;
    }

    mapping(uint256 => ProjectConfig) public projectConfig;

    // the minimum percent increase for new bids above the current bid
    // max uint8 ~= 255, > 100 percent
    // @dev used when determining the increment percentage for any new bid on
    // the minter, across all projects.
    uint8 minterMinBidIncrementPercentage;
    // minimum time remaining in auction after a new bid is placed
    // max uint32 ~= 4.3e9 sec ~= 136 years
    // @dev used when determining the buffer time for any new bid on the
    // minter, across all projects.
    uint32 minterTimeBufferSeconds;
    // minimum inital auction length, in seconds
    // max uint32 ~= 4.3e9 sec ~= 136 years
    // @dev enforced only when artist configures a project
    uint32 minAuctionDurationSeconds;
    // maximum inital auction length, in seconds
    // @dev enforced only when artist configures a project
    uint32 maxAuctionDurationSeconds;

    // function to restrict access to only AdminACL allowed calls
    // @dev defers which ACL contract is used to the core contract
    function _onlyCoreAdminACL(bytes4 _selector) internal {
        require(
            genArtCoreContract_Base.adminACLAllowed(
                msg.sender,
                address(this),
                _selector
            ),
            "Only Core AdminACL allowed"
        );
    }

    function _onlyArtist(uint256 _projectId) internal view {
        require(
            (msg.sender ==
                genArtCoreContract_Base.projectIdToArtistAddress(_projectId)),
            "Only Artist"
        );
    }

    /**
     * @notice Initializes contract to be a Filtered Minter for
     * `_minterFilter`, integrated with Art Blocks core contract
     * at address `_genArt721Address`.
     * @param _genArt721Address Art Blocks core contract address for
     * which this contract will be a minter.
     * @param _minterFilter Minter filter for which
     * this will a filtered minter.
     */
    constructor(
        address _genArt721Address,
        address _minterFilter,
        address _wethAddress
    ) ReentrancyGuard() MinterBase(_genArt721Address) {
        genArt721CoreAddress = _genArt721Address;
        genArtCoreContract_Base = IGenArt721CoreContractV3_Base(
            _genArt721Address
        );
        minterFilterAddress = _minterFilter;
        minterFilter = IMinterFilterV0(_minterFilter);
        require(
            minterFilter.genArt721CoreAddress() == _genArt721Address,
            "Illegal contract pairing"
        );
        weth = IWETH(_wethAddress);
    }

    /**
     * @notice Syncs local maximum invocations of project `_projectId` based on
     * the value currently defined in the core contract.
     * @param _projectId Project ID to set the maximum invocations for.
     * @dev this enables gas reduction after maxInvocations have been reached -
     * core contracts shall still enforce a maxInvocation check during mint.
     */
    function setProjectMaxInvocations(uint256 _projectId) public {
        _onlyArtist(_projectId);
        uint256 maxInvocations;
        uint256 invocations;
        (invocations, maxInvocations, , , , ) = genArtCoreContract_Base
            .projectStateData(_projectId);

        // update storage with results
        projectConfig[_projectId].maxInvocations = uint24(maxInvocations);

        // We need to ensure maxHasBeenInvoked is correctly set after manually syncing the
        // local maxInvocations value with the core contract's maxInvocations value.
        // This synced value of maxInvocations from the core contract will always be greater
        // than or equal to the previous value of maxInvocations stored locally.
        projectConfig[_projectId].maxHasBeenInvoked =
            invocations == maxInvocations;

        emit ProjectMaxInvocationsLimitUpdated(_projectId, maxInvocations);
    }

    /**
     * @notice Manually sets the local maximum invocations of project `_projectId`
     * with the provided `_maxInvocations`, checking that `_maxInvocations` is less
     * than or equal to the value of project `_project_id`'s maximum invocations that is
     * set on the core contract.
     * @dev Note that a `_maxInvocations` of 0 can only be set if the current `invocations`
     * value is also 0 and this would also set `maxHasBeenInvoked` to true, correctly short-circuiting
     * this minter's purchase function, avoiding extra gas costs from the core contract's maxInvocations check.
     * @param _projectId Project ID to set the maximum invocations for.
     * @param _maxInvocations Maximum invocations to set for the project.
     */
    function manuallyLimitProjectMaxInvocations(
        uint256 _projectId,
        uint256 _maxInvocations
    ) external {
        _onlyArtist(_projectId);
        // CHECKS
        // ensure that the manually set maxInvocations is not greater than what is set on the core contract
        uint256 maxInvocations;
        uint256 invocations;
        (invocations, maxInvocations, , , , ) = genArtCoreContract_Base
            .projectStateData(_projectId);
        require(
            _maxInvocations <= maxInvocations,
            "Cannot increase project max invocations above core contract set project max invocations"
        );
        require(
            _maxInvocations >= invocations,
            "Cannot set project max invocations to less than current invocations"
        );
        // EFFECTS
        // update storage with results
        projectConfig[_projectId].maxInvocations = uint24(_maxInvocations);
        // We need to ensure maxHasBeenInvoked is correctly set after manually setting the
        // local maxInvocations value.
        projectConfig[_projectId].maxHasBeenInvoked =
            invocations == _maxInvocations;

        emit ProjectMaxInvocationsLimitUpdated(_projectId, _maxInvocations);
    }

    /**
     * @notice Warning: Disabling purchaseTo is not supported on this minter.
     * This method exists purely for interface-conformance purposes.
     */
    function togglePurchaseToDisabled(uint256 _projectId) external view {
        _onlyArtist(_projectId);
        revert("Action not supported");
    }

    /**
     * @notice projectId => has project reached its maximum number of
     * invocations? Note that this returns a local cache of the core contract's
     * state, and may be out of sync with the core contract. This is
     * intentional, as it only enables gas optimization of mints after a
     * project's maximum invocations has been reached. A false negative will
     * only result in a gas cost increase, since the core contract will still
     * enforce a maxInvocation check during minting. A false positive is not
     * possible because the V3 core contract only allows maximum invocations
     * to be reduced, not increased. Based on this rationale, we intentionally
     * do not do input validation in this method as to whether or not the input
     * `_projectId` is an existing project ID.
     *
     */
    function projectMaxHasBeenInvoked(
        uint256 _projectId
    ) external view returns (bool) {
        return projectConfig[_projectId].maxHasBeenInvoked;
    }

    /**
     * @notice projectId => project's maximum number of invocations.
     * Optionally synced with core contract value, for gas optimization.
     * Note that this returns a local cache of the core contract's
     * state, and may be out of sync with the core contract. This is
     * intentional, as it only enables gas optimization of mints after a
     * project's maximum invocations has been reached.
     * @dev A number greater than the core contract's project max invocations
     * will only result in a gas cost increase, since the core contract will
     * still enforce a maxInvocation check during minting. A number less than
     * the core contract's project max invocations is only possible when the
     * project's max invocations have not been synced on this minter, since the
     * V3 core contract only allows maximum invocations to be reduced, not
     * increased. When this happens, the minter will enable minting, allowing
     * the core contract to enforce the max invocations check. Based on this
     * rationale, we intentionally do not do input validation in this method as
     * to whether or not the input `_projectId` is an existing project ID.
     */
    function projectMaxInvocations(
        uint256 _projectId
    ) external view returns (uint256) {
        return uint256(projectConfig[_projectId].maxInvocations);
    }

    /**
     * @notice projectId => active auction details.
     * @dev reverts if no auction exists for the project.
     */
    function projectActiveAuctionDetails(
        uint256 _projectId
    ) external view returns (Auction memory auction) {
        ProjectConfig storage _projectConfig = projectConfig[_projectId];
        auction = _projectConfig.activeAuction;
        // do not return uninitialized auctions (i.e. auctions that do not
        // exist, and therefore are simply the default struct)
        require(auction.initialized, "No auction exists for this project");
        return auction;
    }

    /**
     * @notice Sets the minimum and maximum values that are settable for
     * `durationSeconds` for all project configurations.
     * Note that the auction duration is the initial duration of the auction,
     * and does not include any extensions that may occur due to new bids being
     * placed near the end of an auction.
     * @param _minAuctionDurationSeconds Minimum auction duration in seconds.
     * @param _maxAuctionDurationSeconds Maximum auction duration in seconds.
     */
    function setAllowableAuctionDurationSeconds(
        uint256 _minAuctionDurationSeconds,
        uint256 _maxAuctionDurationSeconds
    ) external {
        _onlyCoreAdminACL(this.setAllowableAuctionDurationSeconds.selector);
        // CHECKS
        require(
            _maxAuctionDurationSeconds > _minAuctionDurationSeconds,
            "Only max gt min"
        );
        require(_minAuctionDurationSeconds > 0, "only min gt 0");
        // EFFECTS
        minAuctionDurationSeconds = _minAuctionDurationSeconds.toUint32();
        maxAuctionDurationSeconds = _maxAuctionDurationSeconds.toUint32();
        emit AuctionDurationSecondsRangeUpdated(
            _minAuctionDurationSeconds,
            _maxAuctionDurationSeconds
        );
    }

    ////// Auction Functions
    /**
     * @notice Sets auction details for project `_projectId`.
     * @param _projectId Project ID to set future auction details for.
     * @param _timestampStart Timestamp after which new auctions may be
     * started. Note that this is not the timestamp of the auction start, but
     * rather the timestamp after which a auction may be started. Also note
     * that the passed value here must either be in the future, or `0` (which
     * indicates that auctions are immediately startable).
     * @param _auctionDurationSeconds Duration of new auctions, in seconds,
     * before any extensions due to bids being placed inside buffer period near
     * the end of an auction.
     * @param _basePrice reserve price (minimum starting bid price), in wei.
     * Must be greater than 0, but may be as low as 1 wei.
     * @dev `_basePrice` of zero not allowed so we can use zero as a gas-
     * efficient indicator of whether auctions have been configured for a
     * project.
     */
    function configureFutureAuctions(
        uint256 _projectId,
        uint256 _timestampStart,
        uint256 _auctionDurationSeconds,
        uint256 _basePrice
    ) external {
        _onlyArtist(_projectId);
        // CHECKS
        ProjectConfig storage _projectConfig = projectConfig[_projectId];
        require(
            _timestampStart == 0 || block.timestamp < _timestampStart,
            "Only future start times or 0"
        );
        require(
            (_auctionDurationSeconds >= minAuctionDurationSeconds) &&
                (_auctionDurationSeconds <= maxAuctionDurationSeconds),
            "Auction duration out of range"
        );
        require(_basePrice > 0, "Only base price gt 0");
        // EFFECTS
        _projectConfig.timestampStart = _timestampStart.toUint64();
        _projectConfig.auctionDurationSeconds = _auctionDurationSeconds
            .toUint32();
        _projectConfig.basePrice = _basePrice;

        emit ConfiguredFutureAuctions(
            _projectId,
            _timestampStart.toUint64(),
            _auctionDurationSeconds.toUint32(),
            _basePrice
        );

        // sync local max invocations if not initially populated
        // @dev if local max invocations and maxHasBeenInvoked are both
        // initial values, we know they have not been populated.
        if (
            _projectConfig.maxInvocations == 0 &&
            _projectConfig.maxHasBeenInvoked == false
        ) {
            setProjectMaxInvocations(_projectId);
        }
    }

    /**
     * @notice Resets future auction configuration for project `_projectId`,
     * zero-ing out all details having to do with future auction parameters.
     * This is not intended to be used in normal operation, but rather only in
     * case of the need to halt the creation of any future auctions.
     * Does not affect any minter-level project max invocation details.
     * @param _projectId Project ID to reset future auction configuration
     * details for.
     */
    function resetAuctionDetails(uint256 _projectId) external {
        _onlyCoreAdminACL(this.resetAuctionDetails.selector);
        ProjectConfig storage _projectConfig = projectConfig[_projectId];
        // reset to initial values
        _projectConfig.timestampStart = 0;
        _projectConfig.auctionDurationSeconds = 0;
        _projectConfig.basePrice = 0;

        emit ResetAuctionDetails(_projectId);
    }

    /**
     * @notice Inactive function - requires tokenId to bid.
     */
    function purchase(
        uint256 /*_projectId*/
    ) external payable returns (uint256 /*tokenId*/) {
        revert("Call purchase w/tokenId");
    }

    /**
     * @notice Inactive function - requires tokenId to bid
     */
    function purchaseTo(
        address /*_to*/,
        uint256 /*_projectId*/
    ) external payable returns (uint256 /*tokenId*/) {
        revert("Call purchaseTo w/tokenId");
    }

    /**
     * @notice Enters a bid for token `_tokenId` from project `_projectId`.
     * In order to successfully place the bid, the token must be in the
     * auction stage and the bid must be sufficiently greater than the current
     * highest bid. If the bid is unsuccessful, the transaction will revert.
     * If the bid is successful, but outbid by another bid before the auction
     * ends, the funds will be noncustodially returned to the bidder's address,
     * `msg.sender`. A fallback method of sending funds back to the bidder if
     * the address is not accepting ETH is sending funds via WETH (preventing
     * denial of service attacks).
     * @param _projectId Project ID to mint a token on.
     * @param _tokenId Token ID being bidded on
     */
    function createBid(uint256 _projectId, uint256 _tokenId) external payable {
        return createBid_4cM(_projectId, _tokenId);
    }

    /**
     * @notice gas-optimized version of createBid(uint256,uint256).
     */
    function createBid_4cM(
        uint256 _projectId,
        uint256 _tokenId
    ) public payable nonReentrant {
        // CHECKS
        ProjectConfig storage _projectConfig = projectConfig[_projectId];
        Auction storage _auction = _projectConfig.activeAuction;

        // ensure current auction is initialized (and not the default struct)
        require(_auction.initialized, "Auction not started for project");

        // ensure bids for a specific token ID are only applied to the auction
        // for that token ID.
        require(
            _auction.tokenId == _tokenId,
            "Token ID does not match auction"
        );

        // ensure auction is not already ended
        require(_auction.endTime > block.timestamp, "Auction already ended");

        // require bid to be sufficiently greater than current highest bid
        // @dev no overflow enforced automatically by solidity ^8.0.0
        require(
            msg.value >=
                (_auction.currentBid *
                    (100 + minterMinBidIncrementPercentage)) /
                    100,
            "Bid is too low"
        );

        // EFFECTS
        // record previous highest bid details for refunding
        uint256 previousBid = _auction.currentBid;
        address payable previousBidder = _auction.bidder;

        // update auction state
        _auction.currentBid = msg.value;
        _auction.bidder = payable(msg.sender);
        if (_auction.endTime < block.timestamp + minterTimeBufferSeconds) {
            _auction.endTime = (block.timestamp + minterTimeBufferSeconds)
                .toUint64();
        }

        // INTERACTIONS
        // refund previous highest bidder
        _safeTransferETHWithFallback(previousBidder, previousBid);
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and send it as WETH.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            weth.deposit{value: amount}();
            weth.transfer(to, amount);
        }
    }

    /**
     * @notice Gets if price of current bid if auction is configured on project
     * `_projectId`. Also returns currency symbol and address to be being used
     * as payment, which for this minter is ETH only.
     * @param _projectId Project ID to get price information for.
     * @return isConfigured true only if project auctions are configured.
     * @return tokenPriceInWei If auction is live, the current bid value in
     * wei is returned. Note that new bids must be sufficiently greater than
     * the current highest bid to be accepted (see
     * `minterMinBidIncrementPercentage`).
     * If next auction has not yet been initialized, this call will return the
     * minimum starting bid value of the future auction.
     * If auction has ended but not has not yet been settled, the winning bid
     * value will be returned.
     * if isConfigured is false, this value will be 0.
     * @return currencySymbol currency symbol for purchases of project on this
     * minter. This minter always returns "ETH"
     * @return currencyAddress currency address for purchases of project on
     * this minter. This minter always returns null address, reserved for ether
     */
    function getPriceInfo(
        uint256 _projectId
    )
        external
        view
        returns (
            bool isConfigured,
            uint256 tokenPriceInWei,
            string memory currencySymbol,
            address currencyAddress
        )
    {
        ProjectConfig storage _projectConfig = projectConfig[_projectId];
        Auction storage _auction = _projectConfig.activeAuction;
        // base price of zero not allowed when configuring auctions, so use it
        // as indicator of whether auctions are configured for the project
        isConfigured = (_projectConfig.basePrice > 0);
        // only return non-zero price if auction is configured
        if (isConfigured) {
            if (_auction.initialized) {
                // return current bid if auction is initialized
                tokenPriceInWei = _auction.currentBid;
            } else {
                // return base (starting) price if auction has not yet started
                tokenPriceInWei = _projectConfig.basePrice;
            }
        }
        currencySymbol = "ETH";
        currencyAddress = address(0);
    }
}
