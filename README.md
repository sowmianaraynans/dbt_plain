# plain-analytics

> dbt-core analytics foundation for Plain's internal teams — trusted metrics for operations, GTM, customer success, product, and leadership.

---

## Who this is for

Internal Plain stakeholders who need a single, consistent view of the business:

| Team | Primary questions answered |
|---|---|
| **Support Operations** | Thread volume, FRT, TTR, p90 by channel and priority. Agent workload and SLA breach concentration. |
| **Customer Success** | At-risk accounts, per-customer health scores, SLA risk flags by company and month. |
| **GTM / Revenue** | New customer acquisitions per month, active customer base, cohort retention by tier, churn rate. |
| **Product** | Support topic distribution (labels), thread patterns as a proxy for product friction. |
| **Leadership** | New acquisitions trend, active vs churned customer base, projected ARR (annualised from current MRR), SLA compliance, cohort health by tier. |

**Who this is NOT for:** Plain's external customers (Cursor, Linear, Vercel, etc.). They do not query this layer. Customer-facing in-app analytics is a separate planned effort — see [Future plans](#future-in-app-analytics-powered-by-tinybird).

---

## Stack

| Tool | Role |
|---|---|
| **DuckDB** | Local warehouse — zero infrastructure, portable, BigQuery-compatible SQL |
| **dbt-core** | Transformations, tests, lineage, documentation, MetricFlow metric definitions |
| **Python + Faker** | Mock seed data mirroring Plain's GraphQL API field shapes |

> Adapter swap: replace `dbt-duckdb` with `dbt-bigquery` in `requirements.txt` and update `profiles.yml`. Models are identical.

---

## Layers

```
seeds/            Raw CSV data (Plain API shapes)
    ↓  source()
models/raw/       1:1 mirror of source — nothing dropped, renamed, or cast. Append-only.
    ↓  ref()
models/staging/   Cleaned, typed, renamed, deduplicated. company_id preserved on every table.
    ↓  ref()
models/dwh/       Business-ready dimensions and facts. What internal teams query.
```

Each layer has a clear contract. Analysts always know which tier they're on. Staging is the join-safe boundary — no downstream model ever references raw directly.

---

## Models

**Support operations**

| Model | Question answered |
|---|---|
| `fact_thread_measures` | How fast are we resolving? FRT, TTR, p90 by channel / priority / tier — daily grain |
| `fact_sla_performance` | Which companies are breaching SLAs? Who's at critical risk this month? |
| `dim_agent_workload` | Which agents are overloaded? Where are SLA breaches concentrated by agent? |
| `dim_thread` | Thread-level detail with company/customer context and resolution bucket |

**Customer and account**

| Model | Question answered |
|---|---|
| `dim_customer` | Who are our customers? What is their health status and support signal? |
| `dim_company` | What does each account look like — tier, MRR, open threads, SLA breach count? |

**Growth and revenue**

| Model | Key metrics | Question answered |
|---|---|---|
| `fact_company_cohorts` | Logo and MRR retention by cohort month and tier, at-risk MRR | How are our paying accounts retaining? Which cohorts and tiers churn fastest? |
| `fact_mrr_monthly` | Active MRR, new MRR, churned MRR, net new MRR — monthly per tier | Is revenue growing? What was gained and lost each month? Note: expansion MRR requires Stripe. |

---

## Metrics

All metrics are defined once in `models/metrics.yml` using dbt MetricFlow — name, description, grain, and measure. This is the single source of truth. Internal BI reads from this contract. Any future customer-facing analytics layer implements the same definitions, preventing metric divergence between what Plain sees internally and what customers see in the product.

---

## Data assumptions

**Mock data:** Seeds mirror Plain's GraphQL API field shapes. The schema matches `https://graphql.plain.com`. This keeps the repo runnable without credentials.

**Real internal analytics — data does NOT come from the GraphQL API.** The GraphQL API is customer-facing, rate-limited, and not designed for bulk extraction. Internal data flows from:

| Source | What it holds | Ingestion approach |
|---|---|---|
| Internal operational DB / S3 | Customers, companies, threads, events — source of truth | CDC via Airbyte → BigQuery |
| Stripe / billing system | Subscriptions, billing events, actual MRR movement | See note below |
| Attio + other SaaS tools | CRM contacts, account data, product signals | See note below |

**Billing data:** `mrr_usd` is exposed in Plain's GraphQL API but it is a customer-facing field — intended for Plain's customers to see their own account value. It is not a reliable source for Plain's internal billing analytics. Real billing metrics (actual MRR, expansion, contraction, churn revenue) must come from Plain's internal billing system or Stripe directly.

**Ingestion — Polytomic as the consolidation layer:** Plain already has a [Polytomic integration built for its customers](https://attio.com/apps/plain) to sync data between Plain and tools like Attio, Salesforce, and HubSpot. The same Polytomic setup can be leveraged internally to sync billing data, CRM data, and other SaaS sources into BigQuery — avoiding the need to build and maintain separate Fivetran or Airbyte connectors for each tool. Where Polytomic does not cover a source (e.g. Postgres CDC for high-volume event data), Airbyte or Fivetran fill the gap.

---

## Future: in-app analytics powered by Tinybird

This repo is scoped to internal analytics. Customer-facing in-app analytics — Cursor seeing their own support metrics inside Plain's product — is the natural next layer.

**The approach when ready:**

- Extend this repo with a `tinybird/` directory (scaffolded here as a reference), or create a companion repo
- Tinybird data sources sync from BigQuery staging tables, which preserve `company_id` on every row
- Tinybird Pipes implement the same metric logic filtered per `company_id` — one REST endpoint per metric group
- Both internal BI and Tinybird reference `models/metrics.yml` as the shared metric contract

This design ensures one definition of "resolution rate" everywhere — no metric divergence between internal reports and what customers see in the product.

The `tinybird/` directory in this repo contains reference datasource schemas and pipe endpoints to illustrate the pattern. It is not deployed.

---

## Getting started

```bash
# 1. Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Generate mock seed data
python3 ingestion/generate_seeds.py

# 4. Load seeds and run models
dbt seed && dbt run

# 5. Run tests
dbt test

# 6. Explore docs and lineage
dbt docs generate && dbt docs serve
```

---

## Design decisions

**Raw layer is append-only.** Nothing is dropped or cast in raw — it is the permanent record of what came from the source. In production, raw models reference source tables from Airbyte/Fivetran, not seeds.

**Staging is the join-safe boundary.** Types are cast, nulls handled, duplicates removed here. No downstream model references raw directly. `company_id` is preserved on every staging table.

**Customer spine first.** `dim_customer` is the join key for all downstream analytics. Without it, "how many active customers do we have" returns different answers from different tables. The spine is the contract.

**Metrics defined once.** `models/metrics.yml` is the contract — not just documentation. Internal BI and future Tinybird pipes share the same names and definitions. Metric governance is a first-class concern, not an afterthought.

**DuckDB for portability.** Zero infrastructure, runs anywhere, identical SQL to BigQuery. The repo is runnable in a job interview, on a laptop, or in CI without credentials.

---

## Author

Built by [Sowmi](https://linkedin.com/in/) as a demonstration of founding data engineering principles applied to Plain's domain.
