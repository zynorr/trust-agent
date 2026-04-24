// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TrustAgent
 * @notice ERC-8004: Trustless Agent Identity + Reputation Protocol
 * @dev This contract implements a simplified ERC-8004 protocol where:
 *      - Each agent is represented as an ERC721 NFT
 *      - Agents can receive reputation ratings (1-5) from users
 *      - Ratings are stored on-chain with average score calculation
 *      - Prevents double rating from the same address
 */
contract TrustAgent is ERC721, Ownable, AccessControl, Pausable, ReentrancyGuard {
    /// @notice Maximum rating value
    uint8 public constant MAX_RATING = 5;

    /// @notice Minimum rating value
    uint8 public constant MIN_RATING = 1;

    /// @notice Counter for agent token IDs
    uint256 private _agentIdCounter;

    /// @notice Role allowed to register new agents
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    /// @notice Default cooldown between ratings from the same address
    uint256 public constant DEFAULT_RATING_COOLDOWN = 5 minutes;

    /// @notice Minimum delay (in seconds) between ratings by the same address
    uint256 public ratingCooldown;

    /// @notice Default maximum length for metadata URI strings
    uint256 public constant DEFAULT_MAX_METADATA_URI_LENGTH = 256;

    /// @notice Maximum allowed metadata URI length
    uint256 public maxMetadataURILength;

    /// @notice Agent information structure
    struct AgentInfo {
        address creator; // Address that created/registered the agent
        string metadataURI; // URI pointing to agent profile metadata
        uint256 totalRatings; // Total number of ratings received
        uint256 totalScore; // Sum of all ratings (for average calculation)
    }

    /// @notice Mapping from agent token ID to agent information
    mapping(uint256 => AgentInfo) public agents;

    /// @notice Mapping from (agentId => rater) => hasRated
    /// @dev Prevents the same address from rating the same agent twice
    mapping(uint256 => mapping(address => bool)) public hasRated;

    /// @notice Tracks last rating timestamp per rater
    mapping(address => uint256) public lastRatingAt;

    /// @notice Event emitted when a new agent is registered
    /// @param agentId The token ID of the registered agent
    /// @param creator The address that created the agent
    /// @param metadataURI The metadata URI for the agent profile
    event AgentRegistered(uint256 indexed agentId, address indexed creator, string metadataURI);

    /// @notice Event emitted when a rating is submitted
    /// @param agentId The token ID of the agent being rated
    /// @param rater The address submitting the rating
    /// @param rating The rating value (1-5)
    /// @param newAverage The new average rating after this submission
    event RatingSubmitted(uint256 indexed agentId, address indexed rater, uint8 rating, uint256 newAverage);

    /// @notice Event emitted when agent metadata is updated
    /// @param agentId The token ID of the updated agent
    /// @param updatedBy The address that performed the update
    /// @param newMetadataURI The new metadata URI
    event AgentMetadataUpdated(uint256 indexed agentId, address indexed updatedBy, string newMetadataURI);

    /// @notice Event emitted when rating cooldown is updated
    /// @param previousCooldown Previous cooldown in seconds
    /// @param newCooldown New cooldown in seconds
    event RatingCooldownUpdated(uint256 previousCooldown, uint256 newCooldown);

    /// @notice Event emitted when metadata URI length limit is updated
    /// @param previousLimit Previous max URI length
    /// @param newLimit New max URI length
    event MaxMetadataURILengthUpdated(uint256 previousLimit, uint256 newLimit);

    /// @notice Custom error for invalid rating value
    /// @param rating The invalid rating value provided
    error InvalidRating(uint8 rating);

    /// @notice Custom error for agent not found
    /// @param agentId The token ID that doesn't exist
    error AgentNotFound(uint256 agentId);

    /// @notice Custom error for duplicate rating attempt
    /// @param agentId The agent being rated
    /// @param rater The address attempting to rate again
    error AlreadyRated(uint256 agentId, address rater);

    /// @notice Custom error for rating own agent
    /// @param agentId The agent being rated
    error CannotRateOwnAgent(uint256 agentId);

    /// @notice Custom error for unauthorized metadata update
    /// @param agentId The agent being updated
    /// @param caller The address attempting the update
    error UnauthorizedMetadataUpdate(uint256 agentId, address caller);

    /// @notice Custom error for active cooldown between ratings
    /// @param rater Address attempting to rate
    /// @param nextAllowedAt Timestamp when rating becomes allowed
    error RatingCooldownActive(address rater, uint256 nextAllowedAt);

    /// @notice Custom error for invalid metadata URI
    error InvalidMetadataURI();

    /// @notice Custom error for metadata URI exceeding configured max length
    /// @param providedLength Length supplied by caller
    /// @param maxLength Configured maximum length
    error MetadataURITooLong(uint256 providedLength, uint256 maxLength);

    /**
     * @notice Constructor initializes the contract
     * @param name The name of the ERC721 token
     * @param symbol The symbol of the ERC721 token
     */
    constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {
        _agentIdCounter = 0;
        ratingCooldown = DEFAULT_RATING_COOLDOWN;
        maxMetadataURILength = DEFAULT_MAX_METADATA_URI_LENGTH;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRAR_ROLE, msg.sender);
    }

    /**
     * @notice Register a new agent
     * @dev Mints a new ERC721 token representing an agent
     * @param to The address that will own the agent NFT
     * @param metadataURI The URI pointing to the agent's profile metadata
     * @return agentId The token ID of the newly registered agent
     */
    function registerAgent(address to, string memory metadataURI)
        external
        onlyRole(REGISTRAR_ROLE)
        whenNotPaused
        returns (uint256)
    {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        _validateMetadataURI(metadataURI);

        uint256 agentId = _agentIdCounter;
        _agentIdCounter++;

        agents[agentId] = AgentInfo({creator: msg.sender, metadataURI: metadataURI, totalRatings: 0, totalScore: 0});

        _safeMint(to, agentId);

        emit AgentRegistered(agentId, msg.sender, metadataURI);

        return agentId;
    }

    /**
     * @notice Submit a rating for an agent
     * @dev Allows any address to rate an agent (1-5), prevents double rating
     * @param agentId The token ID of the agent to rate
     * @param rating The rating value (must be between MIN_RATING and MAX_RATING)
     */
    function submitRating(uint256 agentId, uint8 rating) external nonReentrant whenNotPaused {
        // Validate agent exists
        if (_ownerOf(agentId) == address(0)) {
            revert AgentNotFound(agentId);
        }

        // Validate rating range
        if (rating < MIN_RATING || rating > MAX_RATING) {
            revert InvalidRating(rating);
        }

        // Prevent rating own agent (owner and creator)
        if (_ownerOf(agentId) == msg.sender || agents[agentId].creator == msg.sender) {
            revert CannotRateOwnAgent(agentId);
        }

        // Prevent double rating
        if (hasRated[agentId][msg.sender]) {
            revert AlreadyRated(agentId, msg.sender);
        }

        // Enforce cooldown between ratings by the same address
        uint256 nextAllowedAt = lastRatingAt[msg.sender] + ratingCooldown;
        if (lastRatingAt[msg.sender] != 0 && block.timestamp < nextAllowedAt) {
            revert RatingCooldownActive(msg.sender, nextAllowedAt);
        }

        // Update agent reputation
        AgentInfo storage agent = agents[agentId];
        agent.totalRatings++;
        agent.totalScore += rating;
        hasRated[agentId][msg.sender] = true;
        lastRatingAt[msg.sender] = block.timestamp;

        // Calculate new average (multiplied by 100 for precision)
        uint256 newAverage = (agent.totalScore * 100) / agent.totalRatings;

        emit RatingSubmitted(agentId, msg.sender, rating, newAverage);
    }

    /**
     * @notice Get agent details
     * @param agentId The token ID of the agent
     * @return owner The current owner of the agent NFT
     * @return creator The address that created the agent
     * @return metadataURI The metadata URI for the agent profile
     */
    function getAgentDetails(uint256 agentId)
        external
        view
        returns (address owner, address creator, string memory metadataURI)
    {
        if (_ownerOf(agentId) == address(0)) {
            revert AgentNotFound(agentId);
        }

        owner = _ownerOf(agentId);
        creator = agents[agentId].creator;
        metadataURI = agents[agentId].metadataURI;
    }

    /**
     * @notice Get reputation summary for an agent
     * @param agentId The token ID of the agent
     * @return totalRatings The total number of ratings received
     * @return averageScore The average rating (multiplied by 100 for precision, e.g., 450 = 4.50)
     */
    function getReputationSummary(uint256 agentId) external view returns (uint256 totalRatings, uint256 averageScore) {
        if (_ownerOf(agentId) == address(0)) {
            revert AgentNotFound(agentId);
        }

        AgentInfo memory agent = agents[agentId];
        totalRatings = agent.totalRatings;

        if (totalRatings == 0) {
            averageScore = 0;
        } else {
            // Return average multiplied by 100 for precision (e.g., 450 = 4.50)
            averageScore = (agent.totalScore * 100) / totalRatings;
        }
    }

    /**
     * @notice Get the average rating as a decimal (e.g., 4.50)
     * @param agentId The token ID of the agent
     * @return The average rating as a decimal number
     */
    function getAverageRating(uint256 agentId) external view returns (uint256) {
        if (_ownerOf(agentId) == address(0)) {
            revert AgentNotFound(agentId);
        }

        AgentInfo memory agent = agents[agentId];
        if (agent.totalRatings == 0) {
            return 0;
        }
        return (agent.totalScore * 100) / agent.totalRatings;
    }

    /**
     * @notice Update metadata URI for a registered agent
     * @dev Only the current owner or original creator can update metadata
     * @param agentId The token ID of the agent
     * @param newMetadataURI The replacement metadata URI
     */
    function updateAgentMetadata(uint256 agentId, string memory newMetadataURI) external whenNotPaused {
        address owner = _ownerOf(agentId);
        if (owner == address(0)) {
            revert AgentNotFound(agentId);
        }

        if (msg.sender != owner && msg.sender != agents[agentId].creator) {
            revert UnauthorizedMetadataUpdate(agentId, msg.sender);
        }
        _validateMetadataURI(newMetadataURI);

        agents[agentId].metadataURI = newMetadataURI;
        emit AgentMetadataUpdated(agentId, msg.sender, newMetadataURI);
    }

    /**
     * @notice Update cooldown between ratings by the same address
     * @param newCooldown New cooldown in seconds
     */
    function setRatingCooldown(uint256 newCooldown) external onlyOwner {
        uint256 previousCooldown = ratingCooldown;
        ratingCooldown = newCooldown;
        emit RatingCooldownUpdated(previousCooldown, newCooldown);
    }

    /**
     * @notice Update the maximum allowed metadata URI length
     * @param newLimit New length limit in bytes (must be > 0)
     */
    function setMaxMetadataURILength(uint256 newLimit) external onlyOwner {
        if (newLimit == 0) {
            revert InvalidMetadataURI();
        }
        uint256 previousLimit = maxMetadataURILength;
        maxMetadataURILength = newLimit;
        emit MaxMetadataURILengthUpdated(previousLimit, newLimit);
    }

    /**
     * @notice Pause state-changing protocol actions
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume state-changing protocol actions
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Check if an address has rated a specific agent
     * @param agentId The token ID of the agent
     * @param rater The address to check
     * @return Whether the address has rated the agent
     */
    function hasAddressRated(uint256 agentId, address rater) external view returns (bool) {
        return hasRated[agentId][rater];
    }

    /**
     * @notice Get the total number of registered agents
     * @return The current agent count
     */
    function getTotalAgents() external view returns (uint256) {
        return _agentIdCounter;
    }

    /**
     * @notice Override tokenURI to return agent metadata URI
     * @param tokenId The token ID
     * @return The metadata URI for the agent
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return agents[tokenId].metadataURI;
    }

    /**
     * @notice Required override for AccessControl + ERC721 inheritance
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Validate metadata URI for emptiness and configured max length
     */
    function _validateMetadataURI(string memory metadataURI) internal view {
        bytes memory uriBytes = bytes(metadataURI);
        if (uriBytes.length == 0) {
            revert InvalidMetadataURI();
        }
        if (uriBytes.length > maxMetadataURILength) {
            revert MetadataURITooLong(uriBytes.length, maxMetadataURILength);
        }
    }
}
