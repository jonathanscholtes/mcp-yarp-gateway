# Example Prompts — MongoDB Analysis Agents

Three agents are deployed to Azure AI Foundry, each connected to the MongoDB MCP server
via the YARP reverse proxy. Use these prompts in the AI Foundry playground, a notebook,
or any client that invokes agents by name.

---

## ContractAnalyst

Analyses the `contracts` collection for portfolio composition, counterparty concentration,
maturity risk, and currency exposure.

**Quick health check**
```
Connect to the MongoDB database and tell me how many contracts are in the contracts_db database.
```

**Portfolio overview**
```
Give me a full portfolio overview of contracts_db. Include:
- Total contract count and breakdown by status
- Top 10 counterparties by total notional
- Breakdown of notional by desk and by book
```

**Maturity risk**
```
Which contracts in contracts_db are maturing within the next 90 days?
List them by counterparty and desk, and flag any counterparty representing more than 20% of total notional.
```

**Currency exposure**
```
Summarise the currency pair exposure across all active contracts in contracts_db.
Which currency pair has the largest share of total notional? Express each pair as a percentage.
```

**Full risk memo**
```
Produce a portfolio risk summary for contracts_db. Cover counterparty concentration,
maturity risk for the next 90 days, and currency pair exposure. Cite specific names and numbers.
```

---

## RiskMemoInvestigator

Cross-references the `risk_memos` and `contracts` collections to surface high-severity
patterns, DV01 / VaR outliers, and desk hotspots.

**Quick health check**
```
Connect to contracts_db and tell me how many risk memos exist, split by severity.
```

**High-severity deep dive**
```
Retrieve the 20 risk memos with the highest var95 in contracts_db.
For each memo, look up the associated contract and tell me the desk, book, and counterparty.
Which desk has the most high-severity exposure?
```

**DV01 outliers**
```
Find all risk memos in contracts_db where the absolute DV01 exceeds 60,000.
List the affected contract IDs, their DV01 values, and the counterparty name from the contracts collection.
```

**Trend analysis**
```
How have high-severity risk memos trended over time in contracts_db?
Aggregate memo counts by day and identify any spikes.
```

**Integrated risk report**
```
Generate a structured risk report for contracts_db covering:
1. An executive summary of overall memo volume and severity distribution
2. Top 5 desks by total var95 across high-severity memos
3. DV01 outliers (abs dv01 > 60,000) linked to contract counterparties
4. Recommended monitoring priorities based on the findings
```

---

## MarketDataSurveillance

Analyses the `market_data` collection for spot price trends, volatility breaches,
and anomalous readings across currency pairs.

**Quick health check**
```
Connect to contracts_db and tell me how many market data snapshots exist and which currency pairs are covered.
```

**Per-pair statistics**
```
For each currency pair in the market_data collection of contracts_db, compute the minimum,
maximum, and average spot price and volatility. Express volatility as a percentage.
```

**Volatility alerts**
```
Find all market data snapshots in contracts_db where volatility exceeds 20%.
For each currency pair that breached the threshold, report the number of breaches,
the highest breach value, and when it occurred.
```

**Spot range analysis**
```
For each currency pair in contracts_db market_data, find the time window with the
widest spot price range. Flag any pair where the max/min ratio exceeds 1.10.
```

**Full surveillance report**
```
Run a complete market surveillance report on contracts_db. Include:
- Per-pair spot and volatility statistics
- All volatility breaches above 20%
- Pairs with spot ranges wider than 10%
- The most recent snapshot values for each pair
- A narrative highlighting the most volatile pair and any data quality concerns
```

---

## Multi-Turn Conversations

### ContractAnalyst — Portfolio drill-down

> **Turn 1**
> ```
> Connect to contracts_db and give me a high-level count of contracts by status.
> ```
>
> **Turn 2**
> ```
> Of the active contracts, which 5 counterparties have the largest total notional?
> ```
>
> **Turn 3**
> ```
> For those top 5 counterparties, which desks are they concentrated in?
> ```
>
> **Turn 4**
> ```
> Do any of those counterparties have contracts maturing within the next 60 days?
> List them with maturity dates and notional values.
> ```
>
> **Turn 5**
> ```
> Summarise everything you've found into a one-page counterparty concentration report
> with specific numbers and a risk rating for each of the top 5 counterparties.
> ```

---

### RiskMemoInvestigator — Escalating risk investigation

> **Turn 1**
> ```
> How many risk memos are in contracts_db and what is the split between high and medium severity?
> ```
>
> **Turn 2**
> ```
> Show me the top 10 high-severity memos ranked by var95. Include memoId, contractId, var95, and dv01.
> ```
>
> **Turn 3**
> ```
> For the top 3 memos by var95, look up the contract document and tell me the desk,
> book, counterparty, and notional.
> ```
>
> **Turn 4**
> ```
> Are there any other high-severity memos linked to the same counterparties you just identified?
> How much total var95 exposure do those counterparties represent?
> ```
>
> **Turn 5**
> ```
> Based on everything found, write an escalation summary I can send to the risk committee.
> Include the top 3 counterparties by var95, their DV01 exposure, and recommended actions.
> ```

---

### MarketDataSurveillance — Volatility investigation

> **Turn 1**
> ```
> List all currency pairs present in contracts_db market_data and the number of snapshots for each.
> ```
>
> **Turn 2**
> ```
> For the pair with the most snapshots, show me the min, max, and average spot and volatility.
> ```
>
> **Turn 3**
> ```
> Have there been any volatility breaches above 20% for that pair? If so, when did they occur?
> ```
>
> **Turn 4**
> ```
> Now check all other pairs for volatility breaches above 20%. Rank them by number of breaches.
> ```
>
> **Turn 5**
> ```
> Write a market alert memo covering the top 3 pairs by breach count. Include the highest
> breach value, date, and a brief interpretation of what the volatility pattern suggests.
> ```

---

## Multi-Agent Workflow (manual sequence)

These prompts demonstrate using all three agents in sequence for an integrated view.

**Step 1 — Portfolio snapshot** *(send to ContractAnalyst)*
```
Give me a brief portfolio snapshot: total contract count, top 3 counterparties by notional,
and how many contracts mature within 60 days.
```

**Step 2 — Risk overlay** *(send to RiskMemoInvestigator)*
```
For the top counterparties identified in the portfolio snapshot, are there high-severity
risk memos in contracts_db? Summarise the var95 and dv01 exposure per counterparty.
```

**Step 3 — Market context** *(send to MarketDataSurveillance)*
```
What is the current volatility environment in contracts_db market_data for the currency
pairs most represented in the active contract portfolio? Flag any pairs above 15% volatility.
```
