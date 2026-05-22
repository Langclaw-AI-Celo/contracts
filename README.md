# Langclaw Contracts

Foundry project for Langclaw's Mantle-first contracts, with live Celo mainnet deployments for agent proof, strategy journaling, and USDT-backed usage billing.

The hackathon-critical contracts are `LangclawRegistry` and `LangclawTradingJournal`. The registry records AI agent decisions, evidence hashes, and signal categories on Mantle; the trading journal records backtest and paper-trading outcomes so every strategy run can be independently checked later.

## Deployed Mantle Contracts

| Contract | Purpose | Mantle mainnet address |
| --- | --- | --- |
| `LangclawRegistry` | Agent decision proof and benchmarking trail | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` |
| `LangclawUsageVault` | Optional MNT billing vault | `0x7e93Ef361e7b54297cF963977bA829E47E59e8E1` |
| `LangclawTradingJournal` | Strategy backtest and paper-trade proof trail | `0xe96e9b76af8c8f32bfa2235d647186826d92fb7d` |

## Deployed Celo Contracts

| Contract | Purpose | Celo mainnet address |
| --- | --- | --- |
| `LangclawRegistry` | Agent decision proof and benchmarking trail | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` |
| `LangclawUsageVault` | MiniPay / USDT usage billing vault | `0x837a2948586de4e7638c742f99e520ffc049bcf7` |
| `LangclawTradingJournal` | Strategy backtest and paper-trade proof trail | `0x69984c20176704685236fd633192d7de1c13a5ec` |

ERC-8004 identity:

- Identity registry: `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`
- Mantle Langclaw agent ID: `94`
- Celo Langclaw agent ID: `9109`
- Celo agent registration tx: `0x1b7cb74378db42551a3cbc81dcd560f337df1593d4ef1cd70ee44ff269bdc7f3`

Registry deployment transaction:
`0xf6f8af14295c86d2f358c32ba15d0669903b122c086dcb0b432d9df8aaec6b6c`

Current Celo USDT vault deployment transaction:
`0xac09eb4b164b51818775cc7f73a33cbdf88428cdc3d853c5ae7ec34999c3e6b2`

Archived native-only Celo vault creation transaction:
`0xbb00e35a375fcafe33e30578bd246c60dddd3584c46bf9114d466206699773df`

Explorer verification note:

- `LangclawRegistry`, `LangclawTradingJournal`, and the live Celo `LangclawUsageVault` address are now verified on Celoscan.
- The live Celo vault is now the USDT-backed deployment at `0x837a2948586de4e7638c742f99e520ffc049bcf7`.
- The older native-only Celo vault at `0x6e1f381458229e8d1ee66d2a0121d4017596b97d` remains verified as an archived deployment.
- Use `cd ../backend && npm run verify:celo-contracts` to submit or prepare the Celo verification artifacts with the deploy-matching compiler settings.

Live decision proof examples:

| Decision | ERC-8004 agent | Signal type | Transaction |
| --- | --- | --- | --- |
| `0` | `94` | `smart-money` | `0x8a598de98fac01d53e696df67a9527de280c4d8cece72ccc4ced91164efa5187` |
| `1` | `94` | `smart-money` | `0x39caaca5fe3a6792c427740342116f309ac02ee0a846c7dbe54f12c86a39a177` |
| `2` | `94` | `liquidity-anomaly` | `0x9956a7574f6144ce831deac3275305939d65503366bc11bd922bc4783eeb5faf` |

## LangclawRegistry

Source: [`src/LangclawRegistry.sol`](src/LangclawRegistry.sol)

Tests: [`test/LangclawRegistry.t.sol`](test/LangclawRegistry.t.sol)

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

- ERC-8004 `agentId`
- Langclaw `runId`
- deterministic `decisionHash`
- evidence URI
- signal type, such as `smart-money` or `liquidity-anomaly`
- recorder wallet
- block timestamp

This is the contract to highlight for Mantle Turing Test Hackathon scoring.

## LangclawTradingJournal

Source: [`src/LangclawTradingJournal.sol`](src/LangclawTradingJournal.sol)

Tests: [`test/LangclawTradingJournal.t.sol`](test/LangclawTradingJournal.t.sol)

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

- ERC-8004 `agentId`
- Langclaw `runId`
- `strategyId` such as `mantle-liquidity-momentum-v1`
- Mantle market or pair address
- deterministic decision and result hashes
- evidence URI
- action, PnL bps, and status (`backtested`, `paper-opened`, or `paper-closed`)
- recorder wallet
- block timestamp

This is the contract to highlight for AI Trading & Strategy scoring without live-funds risk.

## LangclawUsageVault

Source: [`src/LangclawUsageVault.sol`](src/LangclawUsageVault.sol)

Tests: [`test/LangclawUsageVault.t.sol`](test/LangclawUsageVault.t.sol)

`LangclawUsageVault` is an optional billing contract. It holds user MNT deposits on Mantle or USDT deposits on Celo, lets the backend authorize withdrawals, and lets users withdraw only authorized balances.

Mantle mainnet deployment:

- Address: `0x7e93Ef361e7b54297cF963977bA829E47E59e8E1`
- Owner: `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c`
- Withdrawal authority: `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c`

Celo mainnet deployment:

- Address: `0x837a2948586de4e7638c742f99e520ffc049bcf7`
- Owner: `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c`
- Withdrawal authority: `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c`
- Deposit token: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e` (USDT)

Do not mix the vault with the agent proof flow:

- `LangclawRegistry` = Mantle AI decision proof
- `LangclawUsageVault` = optional billing/top-up infrastructure

## Setup

```bash
git submodule update --init
forge build
forge test
```

Requires Foundry: https://book.getfoundry.sh/getting-started/installation

## Deploy Registry

```bash
cp .env.example .env

forge script script/DeployLangclawRegistry.s.sol:DeployLangclawRegistryScript \
  --rpc-url "$MANTLE_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

After deployment, copy the deployed address to `MANTLE_LANGCLAW_REGISTRY_ADDRESS` in `backend/.env`.

## Deploy Optional Usage Vault

```bash
forge script script/DeployLangclawUsageVault.s.sol:DeployLangclawUsageVaultScript \
  --rpc-url "$MANTLE_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

After deployment, copy the deployed address to `MANTLE_LANGCLAW_USAGE_VAULT_ADDRESS` in `backend/.env`.

## Deploy Trading Journal

```bash
forge script script/DeployLangclawTradingJournal.s.sol:DeployLangclawTradingJournalScript \
  --rpc-url "$MANTLE_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

After deployment, copy the deployed address to `MANTLE_LANGCLAW_TRADING_JOURNAL_ADDRESS` in `backend/.env` and set `MANTLE_TRADING_JOURNAL_ENABLED=true`.
