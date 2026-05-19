# minebean-skills

Drop-in skills for autonomous AI agents to interact with [MineBean](https://minebean.com), a 5x5 grid mining protocol on Base.

The skills are portable. They work inside an [AEON Framework](https://github.com/aaronjmars/aeon) fork, Claude Code, or any agent runtime that can execute bash and call EVM contracts via [Foundry `cast`](https://book.getfoundry.sh/cast/).

## Skills in this repo

| Skill | Runtime | What it does |
|---|---|---|
| [`aeon-mine-bean`](./aeon-mine-bean) | AEON Framework | Deploys ETH on the MineBean grid via AEON's GitHub Actions cron. One session covers N consecutive rounds with local sleeps. Auto-claims above thresholds. |
| [`hermes-mine-bean`](./hermes-mine-bean) | Hermes Agent | Same multi-round bash loop, ported to the [agentskills.io](https://agentskills.io) spec for [Hermes Agent](https://hermes-agent.nousresearch.com/). Supports Hermes' zero-Claude-cost `--no-agent --script` cron mode. |

More skills (`stake-bean`, `compound-bean`, `automine-bean`) coming soon.

## Quick start: running `aeon-mine-bean` inside AEON

1. **Fork [aaronjmars/aeon](https://github.com/aaronjmars/aeon)** to your own GitHub account.
2. **Copy `aeon-mine-bean/` from this repo into `skills/aeon-mine-bean/`** in your AEON fork.
3. **Add the schedule entry from [`examples/aeon.yml`](./examples/aeon.yml) to your fork's `aeon.yml`.**
4. **Generate a fresh EOA** for the agent. Note the public address and private key.
5. **Fund the EOA** with a small amount of ETH on Base. ~0.01 ETH covers many days at default config. Treat it as a hot wallet — only fund what you can lose.
6. **Set the required GitHub Actions secrets** in your AEON fork (Settings -> Secrets and variables -> Actions):
   - `AGENT_PRIVATE_KEY` — the EOA's private key
   - `AGENT_ADDRESS` — the EOA's public address
   - `BASE_RPC_URL` — a Base mainnet RPC URL (public works, dedicated is faster)

   **Also required by AEON itself (separate from this skill):**
   - `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` — AEON uses Claude Code to interpret skill instructions. Get one from Anthropic's console or follow AEON's setup guide.
   - Optionally `BANKR_LLM_KEY` if you'd rather route through Bankr's LLM Gateway (cheaper Opus on Vertex AI).

   Each user pays for their own LLM usage. The MineBean team does not provide or subsidize Claude credits.
7. **(Recommended) Run a dry run first.** Set `DRY_RUN=true` as a repo variable. The next cron tick will log what the skill would do without sending any transactions. Verify it looks right.
8. **Remove `DRY_RUN` (or set to `false`) when ready.** The agent will start deploying on the next cron tick.
9. **Monitor `memory/topics/minebean.md`** in your AEON fork for per-run logs.

## Quick start: running `aeon-mine-bean` standalone (no agent framework)

The skill is just a SKILL.md plus bash scripts in `aeon-mine-bean/scripts/`. Any environment that can run bash + Foundry can use it directly:

```bash
# Install Foundry if you don't have it
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone this repo
git clone https://github.com/<your-user>/minebean-skills.git
cd minebean-skills/aeon-mine-bean

# Copy env.example and fill in
cp ../examples/env.example .env
# edit .env with your values

# Source env and run scripts manually
set -a; source .env; set +a
bash scripts/status.sh
bash scripts/deploy.sh
bash scripts/claim.sh eth
```

Wire those calls into your scheduler of choice (systemd timer, cron, GitHub Actions, Cloudflare Workers cron, etc.).

## Quick start: running `hermes-mine-bean` inside Hermes Agent

[Hermes Agent](https://hermes-agent.nousresearch.com/) is Nous Research's managed AI agent runtime with a native cron primitive and the `agentskills.io` open spec.

1. **Install Hermes Agent** following [the official docs](https://hermes-agent.nousresearch.com/docs).
2. **Add this repo as a skill tap and install the skill:**

   ```bash
   hermes skills tap add damo-nu11/minebean-skills
   hermes skills install damo-nu11/minebean-skills/hermes-mine-bean
   ```

3. **Set required env vars.** Hermes will prompt for these on first use, or you can run `hermes setup`:
   - `AGENT_PRIVATE_KEY` — fresh EOA's private key
   - `AGENT_ADDRESS` — fresh EOA's public address
   - `BASE_RPC_URL` — Base mainnet RPC

4. **Schedule it.** Two options:

   **Agent-driven (LLM in the loop, supports notifications and conditional logic):**
   ```bash
   hermes cron create "every 25m" "Run one mine-bean mining batch" --skill hermes-mine-bean
   ```

   **Direct script (zero Claude API cost per fire):**
   ```bash
   hermes cron create "every 25m" \
     --no-agent \
     --script scripts/mine-batch.sh \
     --name minebean-mining \
     --deliver telegram
   ```

5. **Fund the EOA** with a small amount of ETH on Base (~0.01 ETH covers many days at default config).

The `--no-agent` mode runs the bash loop directly without invoking Claude. Same on-chain effect, zero Anthropic API spend per fire. You only pay Base gas.

## Defaults are intentionally tiny

The default `aeon-mine-bean` config deploys 0.0000025 ETH across all 25 blocks per round = ~0.0000625 ETH total. At one fire per 5 minutes, that's roughly $0.05 per day at typical ETH prices. This is by design. A misconfigured cron or a bug shouldn't be able to drain meaningful funds.

There is a hardcoded safety cap of 0.001 ETH per round in `scripts/deploy.sh`. Editing the cap is intentional. If you raise it, you've consciously removed the footgun rail.

## Contracts (Base)

| Contract | Address |
|---|---|
| GridMining | `0x9632495bDb93FD6B0740Ab69cc6c71C9c01da4f0` |
| Bean (ERC20) | `0x5c72992b83E74c4D5200A8E8920fB946214a5A5D` |
| AutoMiner | `0x31358496900D600B2f523d6EdC4933E78F72De89` |
| Staking | `0xfe177128Df8d336cAf99F787b72183D1E68Ff9c2` |

Full reference: [`aeon-mine-bean/references/contracts.md`](./aeon-mine-bean/references/contracts.md)

## Caveats

- GitHub Actions cron has a 5-minute minimum. MineBean rounds are 60 seconds. The skill plays roughly 1 in every 5 rounds. Frame this as passive autonomous mining, not active grid play.
- The agent EOA holds funds and a private key in GitHub Actions secrets. Treat it as a hot wallet. Rotate the key periodically.
- This skill does NOT use MineBean's server-side agent strategies (Sniper, Anti-Winner, Beanpot Hunter, Anti-Loser, Nostradamus). Those run on the protocol's coordinator via signed off-chain configs and are not yet portable to standalone agents. Configure them at [minebean.com](https://minebean.com) if you want managed strategies.

## License

MIT. See [LICENSE](./LICENSE).

## Links

- Web: [minebean.com](https://minebean.com)
- API: [api.minebean.com](https://api.minebean.com)
- Twitter: [@minebean_](https://x.com/minebean_)
- Protocol skill reference: [minebean.com/skill.md](https://minebean.com/skill.md)
