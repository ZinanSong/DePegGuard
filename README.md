# DePegGuard

> On-chain parametric insurance protocol for stablecoin depeg risk  
> Built with Solidity 0.8.20 · Hardhat · Chainlink · OpenZeppelin

## Overview

DePegGuard is a fully automated, permissionless insurance protocol that protects users against stablecoin depeg events. When a covered stablecoin's price falls below a defined threshold for a sustained period, the protocol automatically triggers payouts — no claims assessment, no discretion.

Built as a UCL MSc Financial Technology coursework project (COMP0163 Blockchain Technologies), the protocol demonstrates production-grade smart contract architecture applied to a real DeFi problem.

## Protocol Architecture
## Key Features

- **Parametric triggers** — three severity levels (Mild <0.97, Moderate <0.90, Severe <0.80) with time-weighted average price (TWAP) detection
- **ERC-721 policy NFTs** — each insurance policy is a unique, transferable NFT encoding coverage parameters and settlement state
- **Chainlink oracle integration** — staleness checks, TWAP computation, manipulation-resistant depeg detection
- **DAO governance** — DPG token-weighted voting with 48-hour timelock and emergency guardian
- **Pro-rata solvency scaling** — if aggregate payouts exceed pool liquidity, remaining capital is distributed proportionally across eligible policies
- **Risk-based premium pricing** — premiums scale with volatility (σ), severity level, duration, and pool utilization

## Coverage Products

| Level | Trigger | Observation Window | Typical Premium |
|-------|---------|-------------------|-----------------|
| Mild | Price < 0.97 | 12 hours | ~2% of coverage |
| Moderate | Price < 0.90 | 24 hours | ~4–5% of coverage |
| Severe | Price < 0.80 | 6 hours | ~8–12% of coverage |

## Premium Pricing Model
Where:
- `r(σ)` — volatility-based risk factor (30-day rolling window)
- `S(τ)` — severity multiplier (Mild: 1.0×, Moderate: 2.0×, Severe: 4.0×)
- `D(T)` — duration factor: `1 + 0.1 × (T / 30 days)`
- `U(u)` — utilization adjustment: `1 / (1 - u)`, convex to discourage oversubscription

## Repository Structure
## Test Coverage

End-to-end tests using Hardhat with mock oracle and mock ERC-20:

| Test | Description |
|------|-------------|
| LP deposit | Liquidity accounting verified against on-chain balance |
| Access control | `registerDepeg` gated to owner; external calls rejected |
| No false trigger | Depeg rejected when price above threshold |
| Depeg confirmation | Protocol registers event after 24h observation window |
| Griefing resistance | Empty or invalid token lists rejected at settlement |
| Pro-rata scaling | Payouts scaled proportionally when pool liquidity insufficient |

## Tech Stack

- **Solidity** 0.8.20
- **Hardhat** — local Ethereum environment, deterministic timestamps, mock oracle
- **Chainlink** — `AggregatorV3Interface` price feeds
- **OpenZeppelin** — ERC-721, ERC-20, SafeERC20, Ownable, TimelockController

## Academic Context

Developed for COMP0163 Blockchain Technologies, MSc Financial Technology, University College London (December 2025). Protocol design references Nexus Mutual, Aave, Compound, and MakerDAO governance patterns.
