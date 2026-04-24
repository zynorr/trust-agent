// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TrustAgent} from "../src/TrustAgent.sol";

/**
 * @title DeployTrustAgent
 * @notice Deployment script for TrustAgent contract on Ethereum Sepolia testnet
 * @dev Usage:
 *      forge script script/Deploy.s.sol:DeployTrustAgent --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
 *
 *      Or with private key:
 *      forge script script/Deploy.s.sol:DeployTrustAgent --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv
 */
contract DeployTrustAgent is Script {
    // Contract name and symbol
    string public constant AGENT_NAME = "TrustAgent";
    string public constant AGENT_SYMBOL = "TRUST";

    function run() external {
        // Get deployer address
        address deployer = msg.sender;
        if (tx.origin != address(0)) {
            deployer = tx.origin;
        }

        console.log("Deploying TrustAgent contract...");
        console.log("Deployer address:", deployer);
        console.log("Network:", block.chainid);

        // Deploy contract
        vm.startBroadcast();

        TrustAgent trustAgent = new TrustAgent(AGENT_NAME, AGENT_SYMBOL);

        vm.stopBroadcast();

        // Log deployment information
        console.log("TrustAgent deployed at:", address(trustAgent));
        console.log("Contract name:", AGENT_NAME);
        console.log("Contract symbol:", AGENT_SYMBOL);
        console.log("Owner:", trustAgent.owner());
        console.log("Total agents:", trustAgent.getTotalAgents());

        // Verify deployment
        require(trustAgent.owner() == deployer, "Deployment verification failed: owner mismatch");
        require(trustAgent.getTotalAgents() == 0, "Deployment verification failed: initial agent count should be 0");

        console.log("Deployment successful!");
    }
}
