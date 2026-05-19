---
name: mine-bean
description: Autonomously mine $BEAN on MineBean, a 5x5 grid mining protocol on Base. One session covers N consecutive rounds via a bash loop with local sleeps between rounds; Claude only pays cache load once per N rounds. Uses a bring-your-own EOA funded with a small ETH balance on Base.
homepage: https://minebean.com
twitter: https://x.com/minebean_
network: base
chainId: 8453
license: MIT
---

# mine-bean

Multi-round autonomous mining for $BEAN on Base. One Claude session covers `ROUNDS_PER_SESSION` consecutive rounds (default 5) in a single bash loop with local sleeps. Cost per round is amortised across the session.

Works inside an [AEON Framework](https://github.com/aaronjmars/aeon) fork or any agent runtime that can execute bash.

## Required environment

| Name | Purpose |
|---|---|
| `AGENT_PRIVATE_KEY` | EOA private key with a small ETH balance on Base. Store as a GitHub Actions secret. |
| `AGENT_ADDRESS` | Public address of the agent EOA. |
| `BASE_RPC_URL` | Base mainnet RPC endpoint. |

## Optional environment

| Name | Default | Purpose |
|---|---|---|
| `ROUNDS_PER_SESSION` | `5` | How many consecutive MineBean rounds to play in one Claude session. Higher = lower cost per round. |
| `DEPLOY_BLOCKS` | All 25 blocks | Comma-separated block ids (0..24) to deploy to. |
| `DEPLOY_PER_BLOCK_WEI` | `2500000000000` (`0.0000025 ETH`) | Wei per block. Contract minimum. |
| `CLAIM_THRESHOLD_ETH` | `10000000000000000` (`0.01 ETH`) | Auto-claim pending ETH above this. `0` disables. |
| `CLAIM_THRESHOLD_BEAN` | `1000000000000000000` (`1 BEAN`) | Auto-claim pending BEAN above this. `0` disables. |
| `DRY_RUN` | `false` | If `true`, logs intended actions without sending txs. |

See `references/strategy.md` for capital-at-risk math, EV notes, and recommended starting balances. See `references/contracts.md` for full method signatures and revert reasons.

## Execution

When this skill is invoked, do exactly this:

### 1. Run the mining batch

```
scripts/mine-batch.sh "${ROUNDS_PER_SESSION:-5}"
```

This loops through `ROUNDS_PER_SESSION` rounds in bash, sleeping locally between each. It returns key=value summary lines including `FINAL_PENDING_ETH_WEI`, `FINAL_PENDING_BEAN_WEI`, `DEPLOYS_FIRED`, and `TX_HASHES`.

### 2. Auto-claim if thresholds met

Parse the output. Then:

- If `FINAL_PENDING_ETH_WEI >= CLAIM_THRESHOLD_ETH` and `CLAIM_THRESHOLD_ETH > 0`: run `scripts/claim.sh eth`
- If `FINAL_PENDING_BEAN_WEI >= CLAIM_THRESHOLD_BEAN` and `CLAIM_THRESHOLD_BEAN > 0`: run `scripts/claim.sh bean`

### 3. Log the session

Append one line to `memory/topics/minebean.md`:

```
- <ISO timestamp> · Session: <DEPLOYS_FIRED> deploys, <DEPLOYS_SKIPPED> skipped · TXs: <TX_HASHES>
```

### 4. Exit

Do not retry within this session. The next session will pick up the next batch.

## Safety rules

- The skill defers all deploy/claim safety logic (round-end skip, low balance warning, sanity caps) to `scripts/mine-batch.sh` and `scripts/deploy.sh`. Do not re-implement these in the prompt.
- If `mine-batch.sh` exits non-zero, log the error and exit. Do not retry.
- Never run two `mine-batch.sh` invocations in parallel from the same EOA. The contract enforces one deploy per round per address.

## Wallet conflicts

The MineBean GridMining contract enforces one deploy per round per address. Don't share the AEON agent EOA with:

- An active on-chain AutoMiner config (configured at minebean.com)
- An active server-side agent strategy (Sniper, Anti-Winner, Beanpot Hunter, Anti-Loser, Nostradamus)
- Manual mining from the same address during overlapping rounds

Use a dedicated EOA for AEON.

## Contracts (Base)

- GridMining: `0x9632495bDb93FD6B0740Ab69cc6c71C9c01da4f0`
- Bean (ERC20): `0x5c72992b83E74c4D5200A8E8920fB946214a5A5D`

Full registry in `references/contracts.md`.

## Support

- Web: https://minebean.com
- Twitter: https://x.com/minebean_
- API: https://api.minebean.com

## License

MIT.
