#!/usr/bin/env bash
# status.sh — read current MineBean round state and agent position
#
# Outputs key=value lines that the parent SKILL can parse:
#   ROUND_ID=<uint>
#   TIME_REMAINING=<seconds>
#   ALREADY_DEPLOYED=<true|false>
#   PENDING_ETH_WEI=<uint>
#   PENDING_BEAN_WEI=<uint>
#
# Requires: cast (Foundry), BASE_RPC_URL, AGENT_ADDRESS

set -euo pipefail

: "${BASE_RPC_URL:?BASE_RPC_URL is required}"
: "${AGENT_ADDRESS:?AGENT_ADDRESS is required}"

GRID_MINING="0x9632495bDb93FD6B0740Ab69cc6c71C9c01da4f0"

# Round info: (roundId, startTime, endTime, totalDeployed, timeRemaining, isActive)
round_info=$(cast call "$GRID_MINING" \
    "getCurrentRoundInfo()(uint64,uint256,uint256,uint256,uint256,bool)" \
    --rpc-url "$BASE_RPC_URL")

# Parse the 6-tuple. cast prints values separated by newlines.
mapfile -t round_arr <<< "$round_info"
ROUND_ID="${round_arr[0]}"
TIME_REMAINING="${round_arr[4]}"

# Miner info: (deployedMask, amountPerBlock, checkpointed)
# If deployedMask > 0, the agent already deployed this round.
miner_info=$(cast call "$GRID_MINING" \
    "getMinerInfo(uint64,address)(uint32,uint256,bool)" \
    "$ROUND_ID" "$AGENT_ADDRESS" \
    --rpc-url "$BASE_RPC_URL")
mapfile -t miner_arr <<< "$miner_info"
DEPLOYED_MASK="${miner_arr[0]}"

if [ "$DEPLOYED_MASK" = "0" ]; then
    ALREADY_DEPLOYED="false"
else
    ALREADY_DEPLOYED="true"
fi

# Pending ETH from the combined endpoint.
# (pendingETH, unroastedBEAN, roastedBEAN, uncheckpointedRound)
rewards=$(cast call "$GRID_MINING" \
    "getTotalPendingRewards(address)(uint256,uint256,uint256,uint64)" \
    "$AGENT_ADDRESS" \
    --rpc-url "$BASE_RPC_URL")
mapfile -t rewards_arr <<< "$rewards"
PENDING_ETH_WEI="${rewards_arr[0]}"

# Exact net BEAN (after the 10% roasting fee on mined portion).
# getPendingBEAN returns (gross, fee, net).
bean_breakdown=$(cast call "$GRID_MINING" \
    "getPendingBEAN(address)(uint256,uint256,uint256)" \
    "$AGENT_ADDRESS" \
    --rpc-url "$BASE_RPC_URL")
mapfile -t bean_arr <<< "$bean_breakdown"
PENDING_BEAN_WEI="${bean_arr[2]}"

# Agent ETH balance on Base (for the safety check in SKILL.md)
AGENT_BALANCE_WEI=$(cast balance "$AGENT_ADDRESS" --rpc-url "$BASE_RPC_URL")

echo "ROUND_ID=$ROUND_ID"
echo "TIME_REMAINING=$TIME_REMAINING"
echo "ALREADY_DEPLOYED=$ALREADY_DEPLOYED"
echo "PENDING_ETH_WEI=$PENDING_ETH_WEI"
echo "PENDING_BEAN_WEI=$PENDING_BEAN_WEI"
echo "AGENT_BALANCE_WEI=$AGENT_BALANCE_WEI"
