# plain-analytics

> A portable data foundation for [Plain](https://plain.com) — the support platform for B2B companies.

Built to demonstrate how a **Founding Data Engineer** would approach Plain's data stack from day one:
raw API ingestion → clean staging → trusted gold models → self-serve analytics.

---

## What this is

Plain exposes a rich GraphQL API covering customers, companies, tenants, threads, SLAs, labels, and events.
This repo shows how to turn that API into a **reliable, joinable analytics layer** in a matter of days — not months.

| Layer | What it contains |
|---|---|
| `seeds/` | Realistic mock data mirroring Plain's GraphQL schema (swap for real API extracts) |
| `models/raw/` | 1:1 typed replicas of API responses — append-only, nothing dropped |
| `models/staging/` | Cleaned, renamed, typed, deduplicated — safe to join |
| `models/dwh/` | Business-ready tables: customer spine, thread measures, SLA performance, agent workload |

---

## Stack

| Tool | Role |
|---|---|
| **DuckDB** | Local warehouse — zero infra, portable, BigQuery-compatible SQL |
| **dbt-core** | Transformations, tests, lineage, docs |
| **Python + Faker** | Mock data generation from Plain's GraphQL schema |

> Adapter swap: replace `dbt-duckdb` with `dbt-bigquery` in `requirements.txt` and update `profiles.yml`. Models are identical.

---

## Repo structure

```
plain-analytics/
├── ingestion/
│   └── generate_seeds.py        # Generates mock data mirroring Plain's API schema
├── seeds/                       # CSV seed files (raw API shape)
│   ├── raw_customers.csv
│   ├── raw_companies.csv
│   ├── raw_tenants.csv
│   ├── raw_threads.csv
│   ├── raw_thread_events.csv
│   └── raw_sla_breaches.csv
├── models/
│   ├── raw/                     # Direct mirrors of seed/API data
│   ├── staging/                 # Cleaned, typed, renamed
│   └── dwh/                     # Business-ready, self-serve
│       ├── dim_company.sql
│       ├── dim_customer.sql
│       ├── dim_thread.sql
│       ├── fact_thread_measures.sql
│       ├── fact_sla_performance.sql
│       └── dim_agent_workload.sql
├── tests/                       # dbt generic + singular tests
├── dbt_project.yml
├── profiles.yml
└── requirements.txt
```

---

## The customer spine

The spine is the foundation everything else joins on. It unifies:

- **Customer** — Plain's core entity (individual user)
- **Company** — Account-level grouping (maps to B2B account)
- **Tenant** — Logical workspace/product grouping within a company
- **Tier** — SLA and pricing tier (Enterprise, Pro, Starter)

```sql
-- Every downstream model joins here
select * from dim_customer
where company_tier = 'enterprise'
  and is_active = true
```

---

## Gold models & the questions they answer

| Model | Business question answered |
|---|---|
| `dim_company` | Who are our accounts and what tier/region do they belong to? |
| `dim_customer` | Who are our customers, what company/tier are they on, are they active? |
| `dim_thread` | What are thread-level attributes and status for analysis? |
| `fact_thread_measures` | How fast are we resolving threads? What's median TTR by channel and priority? |
| `fact_sla_performance` | Which customers are we breaching SLAs for? Which tiers are at risk? |
| `dim_agent_workload` | Which agents are overloaded? What's the open thread distribution? |

---

## Getting started

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Generate mock seed data
python ingestion/generate_seeds.py

# 3. Load seeds and run models
dbt seed
dbt run

# 4. Run tests
dbt test

# 5. View docs
dbt docs generate && dbt docs serve
```

---

## Design decisions

**Why DuckDB?** Zero infrastructure, runs anywhere, identical SQL to BigQuery. Makes the repo runnable in a job interview, a laptop, or a CI pipeline without credentials.

**Why seeds over live API calls?** Keeps the demo portable. The ingestion script documents exactly what GraphQL fields are consumed — swapping in a live API key is a one-line change.

**Why raw → staging → gold?** Trust tiers. Raw is append-only and never touched. Staging is where types are cast and nulls handled. Gold is what the business queries. Analysts always know which tier they're on.

**Why a customer spine first?** Because without it, "how many active customers do we have" returns five different answers. The spine is the contract that makes every downstream metric trustworthy.

---

## Author

Built by [Sowmi](https://linkedin.com/in/) as a demonstration of founding data engineering principles applied to Plain's domain.
