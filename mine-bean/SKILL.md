---
name: mine-bean
description: Autonomously mine $BEAN on MineBean, a 5x5 grid mining protocol on Base. Reads round state, deploys ETH across the grid each cycle, and optionally claims rewards when they accumulate. Uses a bring-your-own EOA funded with a small ETH balance on Base.
homepage: https://minebean.com
twitter: https://x.com/minebean_
network: base
chainId: 8453
license: MIT
---

# mine-bean

Drop-in skill that lets an AI agent mine $BEAN on MineBean autonomously. Each scheduled run, the agent reads the current round, checks whether the agent wallet has already deployed this round, and if not, calls `GridMining.deploy()` with a configurable amount of ETH across a configurable set of blocks.

This skill is portable. It works inside an [AEON Framework](https://github.com/aaronjmars/aeon) fork or any Claude Code / agent runtime that can execute bash.

## What it does

When triggered (cron, manual dispatch, or external event):

1. Reads the active MineBean round via `cast call GridMining.getCurrentRoundInfo()`
2. Reads whether `AGENT_ADDRESS` has already deployed this round via `cast call GridMining.getMinerInfo(roundId, AGENT_ADDRESS)`
3. If the agent has NOT deployed this round AND the round is still active:
   - Computes a deploy payload (block selection + ETH amount, see Defaults)
   - Sends `cast send GridMining.deploy(blockIds)` with the ETH value
4. Logs round id, transaction hash, and outcome to `memory/topics/minebean.md`
5. Optionally checks pending rewards. If `pendingETH >= CLAIM_THRESHOLD_ETH` or `pendingBEAN.net >= CLAIM_THRESHOLD_BEAN`, sends the corresponding claim transaction.

## When to run

GitHub Actions cron minimum is 5 minutes. MineBean rounds are 60 seconds, so this skill plays roughly one out of every five rounds. Frame it as passive autonomous mining, not active round-by-round play.

Recommended cadence in `aeon.yml`:

```yaml
schedules:
  - cron: "*/5 * * * *"
    skill: mine-bean
```

## Required environment / secrets

| Name | Purpose | Example |
|---|---|---|
| `AGENT_PRIVATE_KEY` | EOA private key with a small amount of ETH on Base. Store as a GitHub Actions secret. | `0xabc...` |
| `AGENT_ADDRESS` | The agent's public address corresponding to the private key | `0x123...` |
| `BASE_RPC_URL` | Base mainnet RPC endpoint. Public works (`https://mainnet.base.org`) but Alchemy/QuickNode are faster | `https://base-mainnet.g.alchemy.com/v2/KEY` |

## Optional config

| Name | Default | Purpose |
|---|---|---|
| `DEPLOY_BLOCKS` | `"0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24"` | Comma-separated block ids to deploy to (0..24). Default deploys all 25 blocks. |
| `DEPLOY_PER_BLOCK_WEI` | `2500000000000` (`0.0000025 ETH`) | Wei per block. Contract minimum is 0.0000025 ETH. |
| `CLAIM_THRESHOLD_ETH` | `10000000000000000` (`0.01 ETH`) | Pending ETH threshold above which the skill will auto-claim. Set to `0` to disable auto-claim. |
| `CLAIM_THRESHOLD_BEAN` | `1000000000000000000` (`1 BEAN`) | Pending BEAN threshold for auto-claim. Set to `0` to disable. |
| `DRY_RUN` | `false` | If `true`, the skill logs what it would do but does not send any transactions. Use this to validate setup before going live. |

## Capital at risk per fire

With defaults (25 blocks at the minimum 0.0000025 ETH each):

- Per fire: `25 * 0.0000025 = 0.0000625 ETH` deployed onto the grid, plus ~0.0000005 ETH in Base gas
- At 5-minute cron cadence: ~288 fires per day, so ~0.018 ETH per day flowing through the grid

The deployed ETH is **risked, not burned**. Each fire, you are entitled to a share of the winning block's prize pool (with the default 25-block strategy you are always on the winning block) plus a share of the 1 BEAN minted per round. Net economics depend on grid density during your fires. See [`references/strategy.md`](references/strategy.md) for the EV math.

Recommended starting fund for the agent EOA: ~0.01–0.05 ETH. Treat it as a hot wallet. Only fund what you can lose if the EV math goes against you or the wallet is compromised.

If you want to lower the burn rate, set a less frequent cron (e.g., `0 * * * *` = once an hour), reduce `DEPLOY_BLOCKS` to a subset, or run with `DRY_RUN=true` until you're comfortable.

## Contracts (Base)

| Contract | Address |
|---|---|
| GridMining | `0x9632495bDb93FD6B0740Ab69cc6c71C9c01da4f0` |
| Bean (ERC20) | `0x5c72992b83E74c4D5200A8E8920fB946214a5A5D` |
| Staking | `0xfe177128Df8d336cAf99F787b72183D1E68Ff9c2` |
| AutoMiner | `0x31358496900D600B2f523d6EdC4933E78F72De89` |
| Treasury | `0x38F6E74148D6904286131e190d879A699fE3Aeb3` |

Full function signatures and revert reasons live in `references/contracts.md`. Strategy notes and EV math live in `references/strategy.md`.

## Execution steps (Claude instructions)

When this skill is invoked:

### Step 1: Read state

Run `scripts/status.sh`. It will print:
- `ROUND_ID` and `TIME_REMAINING`
- `ALREADY_DEPLOYED` (`true` or `false`)
- `PENDING_ETH_WEI` and `PENDING_BEAN_WEI`

If `TIME_REMAINING < 5` seconds, skip this run. Round is too close to ending to safely include the tx.

If `ALREADY_DEPLOYED` is `true`, skip the deploy step but still check claims.

### Step 2: Deploy (if not already deployed)

If `ALREADY_DEPLOYED` is `false`:

- If `DRY_RUN` is `true`, log "Would deploy [DEPLOY_BLOCKS] with [DEPLOY_PER_BLOCK_WEI] wei per block in round [ROUND_ID]" and skip.
- Otherwise run `scripts/deploy.sh`. Capture the tx hash from the output.

### Step 3: Claim (optional)

If `PENDING_ETH_WEI >= CLAIM_THRESHOLD_ETH` and `CLAIM_THRESHOLD_ETH > 0`:
- Run `scripts/claim.sh eth`

If `PENDING_BEAN_WEI >= CLAIM_THRESHOLD_BEAN` and `CLAIM_THRESHOLD_BEAN > 0`:
- Run `scripts/claim.sh bean`

### Step 4: Log

Append to `memory/topics/minebean.md`:

```
- <ISO timestamp> · Round <ROUND_ID> · Deploy: <tx hash or SKIPPED> · ClaimETH: <tx hash or SKIPPED> · ClaimBEAN: <tx hash or SKIPPED>
```

### Step 5: Notify (optional)

If a Telegram/Discord/Slack integration is wired into the host AEON instance, post a short summary on successful deploy or claim. Skip if no integration available.

## Safety rules

- Never deploy if `TIME_REMAINING < 5` seconds. The tx may not confirm before settlement.
- Never deploy more than `0.001 ETH` per round total (sanity cap above the default `0.0000625 ETH`). If `DEPLOY_PER_BLOCK_WEI` * len(`DEPLOY_BLOCKS`) exceeds this, halt and warn the user that their config exceeds the safety cap. They can override by editing the skill, but the default refuses.
- Never proceed if `AGENT_ADDRESS` ETH balance on Base is less than `1.5 * (per-round cost + estimated gas)`. Log a warning that the wallet needs topping up and exit cleanly.
- If `cast send` reverts with `AlreadyDeployedThisRound`, treat as expected (round was racey) and continue to the claim step.
- Treat all other reverts as errors: log, do not retry inside this run, exit non-zero.

## Don't combine with these on the same wallet

The MineBean GridMining contract enforces one deploy per round per address. If `mine-bean` shares an EOA with any of the following, they will race and one side will revert each round:

- An active on-chain AutoMiner config for the same address (configured at minebean.com)
- An active server-side agent strategy (Sniper, Anti-Winner, Beanpot Hunter, Anti-Loser, Nostradamus) for the same address
- Manual mining from the same address on the website during the same round

Use a dedicated EOA for the AEON agent so it doesn't conflict with your main wallet's activity.

## Out of scope (for future skill versions)

- Server-side agent strategies (Sniper, Anti-Winner, Beanpot Hunter, Anti-Loser, Nostradamus). Those require an off-chain signed agent config and are not yet portable to standalone agents.
- Staking and BEAN compound operations. Add `stake-bean` and `compound-bean` as separate skills if desired.
- Smart block selection based on grid state. Default deploys all 25 blocks for uniform coverage.
- Cross-chain ETH sourcing for agent funding.

## Support

- Twitter: https://x.com/minebean_
- Web: https://minebean.com
- API: https://api.minebean.com
- Issues: open a GitHub issue on this repo

## License

MIT.
