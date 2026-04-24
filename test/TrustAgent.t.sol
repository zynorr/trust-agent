// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TrustAgent} from "../src/TrustAgent.sol";

contract TrustAgentTest is Test {
    TrustAgent public trustAgent;

    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public agentOwner;

    string public constant AGENT_NAME = "TrustAgent";
    string public constant AGENT_SYMBOL = "TRUST";
    string public constant METADATA_URI = "https://example.com/agent/1";

    event AgentRegistered(uint256 indexed agentId, address indexed creator, string metadataURI);

    event RatingSubmitted(uint256 indexed agentId, address indexed rater, uint8 rating, uint256 newAverage);
    event AgentMetadataUpdated(uint256 indexed agentId, address indexed updatedBy, string newMetadataURI);
    event RatingCooldownUpdated(uint256 previousCooldown, uint256 newCooldown);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        agentOwner = makeAddr("agentOwner");

        trustAgent = new TrustAgent(AGENT_NAME, AGENT_SYMBOL);
    }

    // ============ Agent Registration Tests ============

    function test_RegisterAgent() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        assertEq(agentId, 0);
        assertEq(trustAgent.ownerOf(agentId), agentOwner);
        assertEq(trustAgent.tokenURI(agentId), METADATA_URI);
        assertEq(trustAgent.getTotalAgents(), 1);
    }

    function test_RegisterAgent_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(0, owner, METADATA_URI);

        trustAgent.registerAgent(agentOwner, METADATA_URI);
    }

    function test_RegisterAgent_StoresCreator() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        (address ownerAddr, address creator, string memory uri) = trustAgent.getAgentDetails(agentId);

        assertEq(ownerAddr, agentOwner);
        assertEq(creator, owner);
        assertEq(uri, METADATA_URI);
    }

    function test_RegisterMultipleAgents() public {
        uint256 agentId1 = trustAgent.registerAgent(agentOwner, METADATA_URI);
        uint256 agentId2 = trustAgent.registerAgent(user1, "https://example.com/agent/2");

        assertEq(agentId1, 0);
        assertEq(agentId2, 1);
        assertEq(trustAgent.getTotalAgents(), 2);
    }

    function test_RegisterAgent_RevertIfZeroAddress() public {
        vm.expectRevert();
        trustAgent.registerAgent(address(0), METADATA_URI);
    }

    function test_RegisterAgent_RevertIfCallerMissingRegistrarRole() public {
        vm.prank(user1);
        vm.expectRevert();
        trustAgent.registerAgent(agentOwner, METADATA_URI);
    }

    function test_RegisterAgent_WorksAfterGrantingRegistrarRole() public {
        bytes32 registrarRole = trustAgent.REGISTRAR_ROLE();
        trustAgent.grantRole(registrarRole, user1);

        vm.prank(user1);
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        assertEq(agentId, 0);
    }

    function test_RegisterAgent_RevertWhenPaused() public {
        trustAgent.pause();
        vm.expectRevert();
        trustAgent.registerAgent(agentOwner, METADATA_URI);
    }

    // ============ Rating Tests ============

    function test_SubmitRating() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);

        (uint256 totalRatings, uint256 averageScore) = trustAgent.getReputationSummary(agentId);

        assertEq(totalRatings, 1);
        assertEq(averageScore, 500); // 5.00 * 100
    }

    function test_SubmitRating_EmitsEvent() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.expectEmit(true, true, false, true);
        emit RatingSubmitted(agentId, user1, 5, 500);

        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);
    }

    function test_SubmitRating_CalculatesAverage() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        // User1 rates 5
        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);

        // User2 rates 4
        vm.prank(user2);
        trustAgent.submitRating(agentId, 4);

        // User3 rates 3
        vm.prank(user3);
        trustAgent.submitRating(agentId, 3);

        (uint256 totalRatings, uint256 averageScore) = trustAgent.getReputationSummary(agentId);

        assertEq(totalRatings, 3);
        assertEq(averageScore, 400); // (5+4+3)/3 = 4.00 * 100 = 400
    }

    function test_SubmitRating_PreventsDoubleRating() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.AlreadyRated.selector, agentId, user1));
        trustAgent.submitRating(agentId, 4);
    }

    function test_SubmitRating_PreventsRatingOwnAgent() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(agentOwner);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.CannotRateOwnAgent.selector, agentId));
        trustAgent.submitRating(agentId, 5);
    }

    function test_SubmitRating_PreventsCreatorFromRating() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.CannotRateOwnAgent.selector, agentId));
        trustAgent.submitRating(agentId, 5);
    }

    function test_SubmitRating_RevertIfInvalidRating_TooLow() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.InvalidRating.selector, 0));
        trustAgent.submitRating(agentId, 0);
    }

    function test_SubmitRating_RevertIfInvalidRating_TooHigh() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.InvalidRating.selector, 6));
        trustAgent.submitRating(agentId, 6);
    }

    function test_SubmitRating_RevertIfAgentNotFound() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.AgentNotFound.selector, 999));
        trustAgent.submitRating(999, 5);
    }

    function test_SubmitRating_AllValidRatings() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        // Test all valid ratings (1-5)
        for (uint8 i = 1; i <= 5; i++) {
            address rater = makeAddr(string(abi.encodePacked("rater", i)));
            vm.prank(rater);
            trustAgent.submitRating(agentId, i);
        }

        (uint256 totalRatings, uint256 averageScore) = trustAgent.getReputationSummary(agentId);

        assertEq(totalRatings, 5);
        assertEq(averageScore, 300); // (1+2+3+4+5)/5 = 3.00 * 100 = 300
    }

    function test_SubmitRating_EnforcesCooldownAcrossAgents() public {
        uint256 agentId1 = trustAgent.registerAgent(agentOwner, METADATA_URI);
        uint256 agentId2 = trustAgent.registerAgent(user2, "https://example.com/agent/2");

        vm.prank(user1);
        trustAgent.submitRating(agentId1, 5);

        uint256 nextAllowedAt = block.timestamp + trustAgent.ratingCooldown();
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.RatingCooldownActive.selector, user1, nextAllowedAt));
        trustAgent.submitRating(agentId2, 4);
    }

    function test_SubmitRating_AllowsAfterCooldown() public {
        uint256 agentId1 = trustAgent.registerAgent(agentOwner, METADATA_URI);
        uint256 agentId2 = trustAgent.registerAgent(user2, "https://example.com/agent/2");

        vm.prank(user1);
        trustAgent.submitRating(agentId1, 5);

        vm.warp(block.timestamp + trustAgent.ratingCooldown());

        vm.prank(user1);
        trustAgent.submitRating(agentId2, 4);
        assertTrue(trustAgent.hasAddressRated(agentId2, user1));
    }

    function test_SubmitRating_RevertWhenPaused() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        trustAgent.pause();
        vm.prank(user1);
        vm.expectRevert();
        trustAgent.submitRating(agentId, 5);
    }

    // ============ Read Function Tests ============

    function test_GetAgentDetails() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        (address ownerAddr, address creator, string memory uri) = trustAgent.getAgentDetails(agentId);

        assertEq(ownerAddr, agentOwner);
        assertEq(creator, owner);
        assertEq(uri, METADATA_URI);
    }

    function test_GetAgentDetails_RevertIfAgentNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.AgentNotFound.selector, 999));
        trustAgent.getAgentDetails(999);
    }

    function test_GetReputationSummary_NoRatings() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        (uint256 totalRatings, uint256 averageScore) = trustAgent.getReputationSummary(agentId);

        assertEq(totalRatings, 0);
        assertEq(averageScore, 0);
    }

    function test_GetReputationSummary_WithRatings() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);
        vm.prank(user2);
        trustAgent.submitRating(agentId, 3);

        (uint256 totalRatings, uint256 averageScore) = trustAgent.getReputationSummary(agentId);

        assertEq(totalRatings, 2);
        assertEq(averageScore, 400); // (5+3)/2 = 4.00 * 100 = 400
    }

    function test_GetReputationSummary_RevertIfAgentNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.AgentNotFound.selector, 999));
        trustAgent.getReputationSummary(999);
    }

    function test_GetAverageRating() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);
        vm.prank(user2);
        trustAgent.submitRating(agentId, 3);

        uint256 average = trustAgent.getAverageRating(agentId);
        assertEq(average, 400); // 4.00 * 100
    }

    function test_HasAddressRated() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        assertFalse(trustAgent.hasAddressRated(agentId, user1));

        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);

        assertTrue(trustAgent.hasAddressRated(agentId, user1));
        assertFalse(trustAgent.hasAddressRated(agentId, user2));
    }

    function test_GetTotalAgents() public {
        assertEq(trustAgent.getTotalAgents(), 0);

        trustAgent.registerAgent(agentOwner, METADATA_URI);
        assertEq(trustAgent.getTotalAgents(), 1);

        trustAgent.registerAgent(user1, "https://example.com/agent/2");
        assertEq(trustAgent.getTotalAgents(), 2);
    }

    function test_UpdateAgentMetadata_ByOwner() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        string memory newURI = "https://example.com/agent/updated-by-owner";

        vm.expectEmit(true, true, false, true);
        emit AgentMetadataUpdated(agentId, agentOwner, newURI);

        vm.prank(agentOwner);
        trustAgent.updateAgentMetadata(agentId, newURI);
        assertEq(trustAgent.tokenURI(agentId), newURI);
    }

    function test_UpdateAgentMetadata_ByCreator() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        string memory newURI = "https://example.com/agent/updated-by-creator";

        vm.expectEmit(true, true, false, true);
        emit AgentMetadataUpdated(agentId, owner, newURI);

        trustAgent.updateAgentMetadata(agentId, newURI);
        assertEq(trustAgent.tokenURI(agentId), newURI);
    }

    function test_UpdateAgentMetadata_RevertIfUnauthorized() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TrustAgent.UnauthorizedMetadataUpdate.selector, agentId, user1));
        trustAgent.updateAgentMetadata(agentId, "https://example.com/agent/unauthorized");
    }

    function test_UpdateAgentMetadata_RevertWhenPaused() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);
        trustAgent.pause();
        vm.prank(agentOwner);
        vm.expectRevert();
        trustAgent.updateAgentMetadata(agentId, "https://example.com/agent/paused");
    }

    function test_SetRatingCooldown_ByOwner() public {
        uint256 previousCooldown = trustAgent.ratingCooldown();
        uint256 newCooldown = 60;

        vm.expectEmit(false, false, false, true);
        emit RatingCooldownUpdated(previousCooldown, newCooldown);

        trustAgent.setRatingCooldown(newCooldown);
        assertEq(trustAgent.ratingCooldown(), newCooldown);
    }

    function test_SetRatingCooldown_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        trustAgent.setRatingCooldown(60);
    }

    function test_PauseAndUnpause_ByOwner() public {
        assertFalse(trustAgent.paused());
        trustAgent.pause();
        assertTrue(trustAgent.paused());
        trustAgent.unpause();
        assertFalse(trustAgent.paused());
    }

    function test_Pause_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        trustAgent.pause();
    }

    function test_Unpause_RevertIfNotOwner() public {
        trustAgent.pause();
        vm.prank(user1);
        vm.expectRevert();
        trustAgent.unpause();
    }

    // ============ Edge Cases ============

    function test_MultipleAgents_MultipleRatings() public {
        // Register multiple agents
        uint256 agentId1 = trustAgent.registerAgent(agentOwner, METADATA_URI);
        uint256 agentId2 = trustAgent.registerAgent(user1, "https://example.com/agent/2");

        // Rate agent1
        vm.prank(user1);
        trustAgent.submitRating(agentId1, 5);
        vm.prank(user2);
        trustAgent.submitRating(agentId1, 4);

        // Rate agent2
        vm.prank(agentOwner);
        trustAgent.submitRating(agentId2, 3);
        vm.warp(block.timestamp + trustAgent.ratingCooldown());
        vm.prank(user2);
        trustAgent.submitRating(agentId2, 5);

        // Verify agent1 reputation
        (uint256 total1, uint256 avg1) = trustAgent.getReputationSummary(agentId1);
        assertEq(total1, 2);
        assertEq(avg1, 450); // (5+4)/2 = 4.50 * 100

        // Verify agent2 reputation
        (uint256 total2, uint256 avg2) = trustAgent.getReputationSummary(agentId2);
        assertEq(total2, 2);
        assertEq(avg2, 400); // (3+5)/2 = 4.00 * 100
    }

    function test_RatingPrecision() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        // Submit ratings that result in non-integer average
        vm.prank(user1);
        trustAgent.submitRating(agentId, 5);
        vm.prank(user2);
        trustAgent.submitRating(agentId, 4);
        vm.prank(user3);
        trustAgent.submitRating(agentId, 4);

        // (5+4+4)/3 = 4.33... * 100 = 433 (rounded down)
        (uint256 totalRatings, uint256 averageScore) = trustAgent.getReputationSummary(agentId);

        assertEq(totalRatings, 3);
        assertEq(averageScore, 433); // 13/3 * 100 = 433.33... -> 433
    }

    function test_ERC721Functionality() public {
        uint256 agentId = trustAgent.registerAgent(agentOwner, METADATA_URI);

        // Test ERC721 standard functions
        assertEq(trustAgent.ownerOf(agentId), agentOwner);
        assertEq(trustAgent.balanceOf(agentOwner), 1);
        assertEq(trustAgent.tokenURI(agentId), METADATA_URI);
    }

    function test_security() public {}
}
