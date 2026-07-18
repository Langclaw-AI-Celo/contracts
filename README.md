# Langclaw Contracts

Foundry project for Langclaw's Celo-first proof and usage contracts. Mantle
deployments remain documented as optional legacy support, but the current product
submission is Celo mainnet.

## Contract Set

| Contract | Purpose |
| --- | --- |
| `LangclawRegistry` | Records AI agent decisions, evidence hashes, run IDs, signal types, recorder wallet, and timestamp |
| `LangclawTradingJournal` | Records Strategy Lab backtests and paper-trade outcomes with deterministic decision/result hashes |
| `LangclawUsageVault` | Holds Celo USDT usage-credit deposits and supports backend-authorized withdrawals |

The contracts do not execute trades, custody strategy positions, or call model
providers.

## Deployed Celo Contracts

| Contract | Celo mainnet address | Notes |
| --- | --- | --- |
| `LangclawRegistry` | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` | Agent decision proof |
| `LangclawTradingJournal` | `0x69984c20176704685236fd633192d7de1c13a5ec` | Strategy backtest and paper-trade proof |
| `LangclawUsageVault` | `0x837a2948586de4e7638c742f99e520ffc049bcf7` | MiniPay-ready Celo USDT usage vault; native CELO deposits are disabled |
| Celo USDT | `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e` | Vault deposit token |

Agent identity:

| Item | Value |
| --- | --- |
| ERC-8004 identity registry | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| Celo ERC-8004 agent ID | `9109` |
| Celo agent registration tx | `0x1b7cb74378db42551a3cbc81dcd560f337df1593d4ef1cd70ee44ff269bdc7f3` |
| Celo Self Agent ID | `133` |
| Celo Self Agent ID tx | `0x3c7d0cc69f77d2aef5ab21bfe703d0f33f7037d5e2162209d78b23b5c3f1cde6` |
| Agent owner / recorder | `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c` |

Current Celo proof examples:

| Record | Agent | Signal / Status | Transaction |
| --- | --- | --- | --- |
| Registry decision `47` | ERC-8004 agent ID `9109` | `campaign-backend-proof` | `0xb50e7bd12af0cbca9a6246a80f1976da753d359fbd1553458712b43aa40681b1` |
| Registry decision `1` | Self Agent ID `133` | `smart-money` | `0x2a2f94c40e2b5c080bd330f43f3ce6bc6b05e054b6626ce3ab2716220f0d3211` |

Latest ERC-8004 decision run:

- `github-backend-433b125-2026-06-08`
- Evidence URI:
  `https://github.com/Langclaw-AI-Celo/backend/commit/433b12562c6472dae9e3ff5a1286596a0420eaeb`

## Deployed Mantle Contracts

| Contract | Mantle mainnet address | Notes |
| --- | --- | --- |
| `LangclawRegistry` | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` | Optional explicit Mantle analysis proof |
| `LangclawUsageVault` | `0x7e93Ef361e7b54297cF963977bA829E47E59e8E1` | Optional MNT billing vault |
| `LangclawTradingJournal` | `0xe96e9b76af8c8f32bfa2235d647186826d92fb7d` | Optional strategy journal |

## Explorer Verification

- `LangclawRegistry`, `LangclawTradingJournal`, and the live Celo
  `LangclawUsageVault` are verified on Celoscan.
- The latest proof references above were rechecked during the 2026-06-11
  backend eligibility and proof-readiness pass. If local audits report
  `missing git origin remote` for the checkouts, verify that the workspace root
  contains the remote origin.
- The latest registry write now remains the ERC-8004 decision `#47` for agent
  `9109`, while the latest Self-linked proof example remains decision `#1` for
  agent `133`.
- `cd ../backend && npm run check:celo-proof -- --json` now reports
  `ready: true` with status `ready`, because the default proof path prefers the
  ERC-8004 campaign agent `9109`.
- Self Agent ID `133` remains documented for linked-proof and
  human-verification flows, not as the primary campaign proof writer.
- The live Celo vault is the USDT-backed deployment at
  `0x837a2948586de4e7638c742f99e520ffc049bcf7`.
- New token-enabled vault deployments are documented from
  `src/LangclawUsageVault.sol`. The backend verifier can still switch to the
  archived native-only snapshot when it detects the older Celo deployment.
- The older native-only Celo vault at
  `0x6e1f381458229e8d1ee66d2a0121d4017596b97d` remains archived and verified
  for historical reference.
- Use `cd ../backend && npm run verify:celo-contracts` to submit or prepare Celo
  verification artifacts with deploy-matching compiler settings.

## Source Files

| Contract | Source | Tests |
| --- | --- | --- |
| `LangclawRegistry` | [`src/LangclawRegistry.sol`](src/LangclawRegistry.sol) | [`test/LangclawRegistry.t.sol`](test/LangclawRegistry.t.sol) |
| `LangclawTradingJournal` | [`src/LangclawTradingJournal.sol`](src/LangclawTradingJournal.sol) | [`test/LangclawTradingJournal.t.sol`](test/LangclawTradingJournal.t.sol) |
| `LangclawUsageVault` | [`src/LangclawUsageVault.sol`](src/LangclawUsageVault.sol) | [`test/LangclawUsageVault.t.sol`](test/LangclawUsageVault.t.sol) |

## `LangclawRegistry`

```solidity
function recordAgentDecision(
    uint256 agentId,
    string calldata runId,
    bytes32 decisionHash,
    string calldata evidenceUri,
    string calldata signalType
) external returns (uint256 decisionId);

function getDecision(uint256 decisionId) external view returns (AgentDecision memory);
```

Each record stores:

- ERC-8004 or Self-linked `agentId`.
- Langclaw `runId`.
- Deterministic `decisionHash`.
- Evidence URI.
- Signal type, such as `smart-money` or `liquidity-anomaly`.
- Recorder wallet.
- Block timestamp.

This is the main contract to highlight for Celo AI agent decision proof.

## `LangclawTradingJournal`

```solidity
function recordStrategyRun(
    uint256 agentId,
    string calldata runId,
    string calldata strategyId,
    string calldata market,
    bytes32 decisionHash,
    bytes32 resultHash,
    string calldata evidenceUri,
    string calldata action,
    int256 pnlBps,
    string calldata status
) external returns (uint256 recordId);

function getRecord(uint256 recordId) external view returns (StrategyRecord memory);
```

Each record stores:

- Agent ID.
- Langclaw `runId`.
- Strategy ID, such as `celo-liquidity-momentum-v1`.
- Market or pair address.
- Deterministic decision and result hashes.
- Evidence URI.
- Action, PnL bps, and status such as `backtested`, `paper-opened`, or
  `paper-closed`.
- Recorder wallet.
- Block timestamp.

This contract supports Strategy Lab demos without live-funds risk.

## `LangclawUsageVault`

```solidity
function deposit(bytes32 depositReference) external payable;

function depositTokenAmount(
    bytes32 depositReference,
    uint256 amount
) external;

function authorizeWithdrawal(
    address payer,
    uint256 amount,
    bytes32 withdrawalId
) external;

function withdraw(uint256 amount) external;

function vaultBalance() public view returns (uint256);
```

For the Celo deployment:

- Address: `0x837a2948586de4e7638c742f99e520ffc049bcf7`
- Owner: `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c`
- Withdrawal authority: `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c`
- Deposit token: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e` (USDT)
- Production deposit path: `depositTokenAmount(...)`
- Native CELO deposit behavior on the live vault: reverts with
  `UnsupportedNativeDeposit()`

The vault can also support native deposits when deployed with
`depositToken = address(0)`, but the current Celo production vault is token-based
USDT billing.

For the current live Celo vault:

- Approve USDT, then call `depositTokenAmount(...)` for deposits.
- Native `deposit(...)` is only for native-billing deployments and will revert
  with `UnsupportedNativeDeposit()` on the live USDT-backed vault.

### ERC-8021 Calldata Compatibility

Langclaw Celo clients may append an ERC-8021 Schema 0 attribution suffix after
the normal ABI payload for registry, journal, deposit, and withdrawal calls.
The contract entry points accept the trailing calldata without changing stored
values. Tests cover registry decisions, strategy proofs, native deposits, token
deposits, and token withdrawals.

The suffix does not change a function selector, ABI, bytecode, contract
address, or deployed contract. Mantle calls remain untagged. This compatibility
update does not require a contract deployment.

Campaign verification should prove the token-backed path, not only source
verification:

1. Confirm Celoscan shows `LangclawUsageVault` at
   `0x837a2948586de4e7638c742f99e520ffc049bcf7`.
2. Confirm the vault deposit token is Celo USDT
   `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`.
3. Confirm the frontend `/usage` flow approves USDT before submitting
   `depositTokenAmount(...)`.
4. Confirm the backend `POST /api/usage/deposit/verify` flow credits only after
   matching a confirmed vault deposit event.

## Setup

```bash
git submodule update --init
forge build
forge test
```

Requires Foundry: https://book.getfoundry.sh/getting-started/installation

The local Foundry profile uses `solc 0.8.24`, optimizer `200`, and `via_ir =
true`. The backend verifier rebuilds Celo verification bundles with deploy-
matching `solc 0.8.35` settings.

Standalone Foundry usage in this repo reads `CELO_RPC_URL` and `PRIVATE_KEY`
from `contracts/.env`. Backend deployment helpers instead use
`CELO_CHAIN_RPC_URL` plus `CELO_DEPLOYER_PRIVATE_KEY` or `CELO_PRIVATE_KEY`,
then write the resulting addresses back into `backend/.env`.

## Deploy Registry

```bash
cp .env.example .env
export CELO_RPC_URL="${CELO_CHAIN_RPC_URL:-$CELO_RPC_URL}"
export PRIVATE_KEY="${CELO_DEPLOYER_PRIVATE_KEY:-$PRIVATE_KEY}"

forge script script/DeployLangclawRegistry.s.sol:DeployLangclawRegistryScript \
  --rpc-url "$CELO_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

After deployment, copy the deployed address to
`CELO_LANGCLAW_REGISTRY_ADDRESS` in `backend/.env`.

These direct Foundry examples use the contracts-local `.env.example` variable
names (`CELO_RPC_URL`, `PRIVATE_KEY`). The backend deployment helpers below use
the application env names (`CELO_CHAIN_RPC_URL`,
`CELO_DEPLOYER_PRIVATE_KEY`/`CELO_PRIVATE_KEY`) and are the safer default when
you want runtime docs and `.env` values to stay aligned.

## Deploy Usage Vault

```bash
export CELO_RPC_URL="${CELO_CHAIN_RPC_URL:-$CELO_RPC_URL}"
export PRIVATE_KEY="${CELO_DEPLOYER_PRIVATE_KEY:-$PRIVATE_KEY}"

forge script script/DeployLangclawUsageVault.s.sol:DeployLangclawUsageVaultScript \
  --rpc-url "$CELO_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

For a Celo USDT vault, deploy with the USDT token constructor path used by the
backend deployment script, then copy the deployed address to
`CELO_LANGCLAW_USAGE_VAULT_ADDRESS` in `backend/.env`.

Required vault constructor env:

```bash
export LANGCLAW_USAGE_VAULT_OWNER=
export LANGCLAW_USAGE_VAULT_WITHDRAWAL_AUTHORITY=
export LANGCLAW_USAGE_VAULT_DEPOSIT_TOKEN=0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e
```

## Deploy Trading Journal

```bash
export CELO_RPC_URL="${CELO_CHAIN_RPC_URL:-$CELO_RPC_URL}"
export PRIVATE_KEY="${CELO_DEPLOYER_PRIVATE_KEY:-$PRIVATE_KEY}"

forge script script/DeployLangclawTradingJournal.s.sol:DeployLangclawTradingJournalScript \
  --rpc-url "$CELO_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

After deployment, copy the deployed address to
`CELO_LANGCLAW_TRADING_JOURNAL_ADDRESS` in `backend/.env` and set
`CELO_TRADING_JOURNAL_ENABLED=true`.

## Backend Deployment Helpers

The backend repo wraps the deployment scripts with chain-aware env writing:

```bash
cd ../backend
npm run deploy:registry -- --chain celo --write-env
npm run deploy:usage-vault -- --chain celo --write-env
npm run deploy:trading-journal -- --chain celo --write-env
npm run register:agent -- --chain celo --write-env
npm run verify:celo-contracts
```

Prefer these backend helpers when the goal is to keep `.env` values synchronized
with the application runtime.
