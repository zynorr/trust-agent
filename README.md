# TrustAgent

TrustAgent is a Foundry-based Solidity project for on-chain autonomous agent identity and reputation, inspired by ERC-8004.

It lets anyone register an agent as an ERC721 NFT and lets other addresses submit a single rating (1-5) per agent.

## Features

- Agent registration as ERC721 NFTs with metadata URIs
- Reputation tracking with `totalRatings` and `totalScore`
- Average rating returned with 2-decimal fixed precision (`x100`)
- Double-rating prevention per `(agentId, rater)`
- Self-rating prevention for the current agent owner
- Custom errors for gas-efficient reverts

## Project Layout

```text
src/TrustAgent.sol        # Core protocol contract
test/TrustAgent.t.sol     # Foundry unit tests
script/Deploy.s.sol       # Deployment script (Sepolia-ready)
foundry.toml              # Foundry config
```

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity `0.8.26` (managed by Foundry config)

## Quick Start

```bash
forge build
forge test -vv
```

## Deploy

Set environment variables:

```bash
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_INFURA_KEY"
export PRIVATE_KEY="YOUR_PRIVATE_KEY"
```

Run deployment:

```bash
forge script script/Deploy.s.sol:DeployTrustAgent \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv
```

## Contract API

- `registerAgent(address to, string metadataURI) -> uint256`
- `submitRating(uint256 agentId, uint8 rating)`
- `getAgentDetails(uint256 agentId) -> (owner, creator, metadataURI)`
- `getReputationSummary(uint256 agentId) -> (totalRatings, averageScoreX100)`
- `getAverageRating(uint256 agentId) -> uint256`
- `hasAddressRated(uint256 agentId, address rater) -> bool`
- `getTotalAgents() -> uint256`

## Notes

- Average values are integer-truncated in fixed-point form (`x100`).
- Example: ratings `5, 4, 4` produce `433` (representing `4.33`).
