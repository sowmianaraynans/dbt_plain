"""
generate_seeds.py
-----------------
Generates realistic mock CSV seed files that mirror Plain's GraphQL API schema.

Entities generated (matching Plain's API):
  - customers       → /graphql/customers
  - companies       → /graphql/companies
  - tenants         → /graphql/tenants
  - threads         → /graphql/threads
  - thread_events   → /graphql/events (status transitions, assignments)
  - sla_breaches    → /graphql/tiers/service-level-agreements

To use real data instead: replace each CSV with the output of the
corresponding GraphQL query. Field names are kept identical to the API response.
"""

import csv
import random
import uuid
from datetime import datetime, timedelta
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
SEED_DIR = Path(__file__).parent.parent / "seeds"
SEED_DIR.mkdir(exist_ok=True)

random.seed(42)

N_COMPANIES   = 30
N_CUSTOMERS   = 120
N_TENANTS     = 40
N_THREADS     = 500
N_EVENTS_PER_THREAD = 4

TIERS         = ["enterprise", "pro", "starter", "free"]
TIER_WEIGHTS  = [0.10, 0.25, 0.35, 0.30]
CHANNELS      = ["email", "slack", "chat", "api", "microsoft_teams"]
PRIORITIES    = ["urgent", "high", "normal", "low"]
THREAD_STATUS = ["todo", "snoozed", "done"]
LABEL_TYPES   = ["bug", "feature_request", "billing", "onboarding", "security", "general"]
REGIONS       = ["us-east", "eu-west", "ap-south", "us-west"]


def uid() -> str:
    return str(uuid.uuid4())


def ts(days_ago_max=180, days_ago_min=0) -> str:
    delta = timedelta(days=random.uniform(days_ago_min, days_ago_max),
                      hours=random.uniform(0, 23),
                      minutes=random.uniform(0, 59))
    return (datetime.utcnow() - delta).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_csv(filename: str, rows: list[dict]) -> None:
    path = SEED_DIR / filename
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"  ✓ {filename:35s} {len(rows):>5} rows → {path}")


# ── Companies ─────────────────────────────────────────────────────────────────
company_names = [
    "Cursor", "Raycast", "Granola", "Linear", "Vercel", "Supabase", "Retool",
    "Clerk", "Resend", "Loops", "Liveblocks", "Trigger.dev", "Inngest", "Neon",
    "PlanetScale", "Turso", "Render", "Railway", "Fly.io", "Deno", "Val.town",
    "Coherence", "Zuplo", "Speakeasy", "Stainless", "Mintlify", "Fern", "Scalar",
    "Encore", "Depot"
]

companies = []
company_ids = []
for i in range(N_COMPANIES):
    cid = uid()
    company_ids.append(cid)
    tier = random.choices(TIERS, weights=TIER_WEIGHTS)[0]
    created = ts(days_ago_max=365, days_ago_min=60)
    companies.append({
        "id":                cid,
        "name":              company_names[i],
        "tier":              tier,
        "domain_name":       company_names[i].lower().replace(".", "") + ".com",
        "region":            random.choice(REGIONS),
        "is_active":         random.choices([True, False], weights=[0.85, 0.15])[0],
        "mrr_usd":           {"enterprise": random.randint(3000, 20000),
                              "pro": random.randint(500, 3000),
                              "starter": random.randint(50, 500),
                              "free": 0}[tier],
        "created_at":        created,
        "updated_at":        ts(days_ago_max=30, days_ago_min=0),
    })

write_csv("raw_companies.csv", companies)


# ── Tenants ───────────────────────────────────────────────────────────────────
# Tenants are logical workspaces within a company (e.g. prod vs staging, or a sub-product)
tenants = []
tenant_ids = []
for _ in range(N_TENANTS):
    tid = uid()
    tenant_ids.append(tid)
    company = random.choice(companies)
    tenants.append({
        "id":           tid,
        "external_id":  f"tenant_{tid[:8]}",
        "company_id":   company["id"],
        "name":         random.choice(["production", "staging", "enterprise-workspace",
                                       "growth-team", "platform", "api-customers"]),
        "tier":         company["tier"],
        "created_at":   ts(days_ago_max=300, days_ago_min=30),
        "updated_at":   ts(days_ago_max=10, days_ago_min=0),
    })

write_csv("raw_tenants.csv", tenants)


# ── Customers ─────────────────────────────────────────────────────────────────
first_names = ["Alice","Bob","Carlos","Diana","Ethan","Fiona","George","Hannah",
               "Ivan","Julia","Kevin","Laura","Mike","Nina","Oscar","Paula",
               "Quinn","Rachel","Sam","Tina","Uma","Victor","Wendy","Xander",
               "Yara","Zoe","Amir","Bella","Chen","Dara"]
last_names  = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller",
               "Davis","Wilson","Taylor","Anderson","Thomas","Jackson","White",
               "Harris","Martin","Thompson","Moore","Young","Allen","King",
               "Wright","Scott","Green","Baker","Adams","Nelson","Carter",
               "Mitchell","Perez"]

customers = []
customer_ids = []
for i in range(N_CUSTOMERS):
    cid = uid()
    customer_ids.append(cid)
    company = random.choice(companies)
    tenant = random.choice([t for t in tenants if t["company_id"] == company["id"]] or [random.choice(tenants)])
    fn = random.choice(first_names)
    ln = random.choice(last_names)
    created = ts(days_ago_max=300, days_ago_min=1)
    customers.append({
        "id":                   cid,
        "full_name":            f"{fn} {ln}",
        "short_name":           fn,
        "email":                f"{fn.lower()}.{ln.lower()}@{company['domain_name']}",
        "company_id":           company["id"],
        "tenant_id":            tenant["id"],
        "company_tier":         company["tier"],
        "is_spam":              False,
        "status":               random.choices(["active", "idle", "churned"],
                                               weights=[0.65, 0.25, 0.10])[0],
        "created_at":           created,
        "updated_at":           ts(days_ago_max=14, days_ago_min=0),
    })

write_csv("raw_customers.csv", customers)


# ── Threads ───────────────────────────────────────────────────────────────────
thread_titles = [
    "API rate limits hitting production", "Billing invoice discrepancy",
    "Webhook not firing on thread.created", "Can't add team member to workspace",
    "GraphQL schema question on tenants", "SLA config for enterprise tier",
    "Slack integration not syncing", "Feature request: bulk thread export",
    "Thread assignment not working", "OAuth token expiring too fast",
    "SDK types out of date", "Migration from Intercom — data import",
    "Custom fields on customer objects", "Email routing broken after domain change",
    "AI suggested replies quality feedback", "Priority escalation not triggering",
    "GDPR data deletion request", "SSO setup for enterprise workspace",
    "Webhook signature verification failing", "Help center article indexing delay",
]

agent_ids = [uid() for _ in range(8)]  # simulate 8 support agents
agent_names = ["Alex Chen", "Priya Patel", "Tom Walker", "Sarah Kim",
               "James O'Brien", "Maria Santos", "David Liu", "Emma Brown"]

threads = []
thread_ids = []
for _ in range(N_THREADS):
    tid = uid()
    thread_ids.append(tid)
    customer = random.choice(customers)
    created = ts(days_ago_max=90, days_ago_min=0)
    created_dt = datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ")

    status = random.choices(THREAD_STATUS, weights=[0.35, 0.10, 0.55])[0]
    priority = random.choices(PRIORITIES, weights=[0.05, 0.15, 0.60, 0.20])[0]
    channel = random.choices(CHANNELS, weights=[0.40, 0.25, 0.15, 0.15, 0.05])[0]

    first_response_mins = random.randint(2, 480) if status != "todo" else None
    resolution_mins = (random.randint(first_response_mins or 5, 4320)
                       if status == "done" else None)

    assigned_agent_idx = random.randint(0, 7)

    threads.append({
        "id":                        tid,
        "external_id":               f"ext_{tid[:8]}",
        "customer_id":               customer["id"],
        "company_id":                customer["company_id"],
        "tenant_id":                 customer["tenant_id"],
        "company_tier":              customer["company_tier"],
        "title":                     random.choice(thread_titles),
        "status":                    status,
        "status_detail":             random.choice(["created", "replied_to", "in_progress", None]),
        "priority":                  priority,
        "channel":                   channel,
        "label":                     random.choice(LABEL_TYPES + [None, None]),
        "assigned_agent_id":         agent_ids[assigned_agent_idx],
        "assigned_agent_name":       agent_names[assigned_agent_idx],
        "first_response_time_mins":  first_response_mins,
        "resolution_time_mins":      resolution_mins,
        "message_count":             random.randint(1, 24),
        "is_escalated":              random.choices([True, False], weights=[0.08, 0.92])[0],
        "created_at":                created,
        "updated_at":                ts(days_ago_max=30, days_ago_min=0),
        "resolved_at":               (
            (created_dt + timedelta(minutes=resolution_mins)).strftime("%Y-%m-%dT%H:%M:%SZ")
            if resolution_mins else None
        ),
    })

write_csv("raw_threads.csv", threads)


# ── Thread events (status transitions + assignments) ──────────────────────────
event_types = ["thread_created", "thread_status_transitioned", "thread_assignment_transitioned",
               "thread_priority_changed", "thread_labels_changed", "thread_escalated",
               "message_sent", "message_received", "note_created"]

events = []
for thread in threads:
    n = random.randint(2, N_EVENTS_PER_THREAD + 2)
    thread_created_dt = datetime.strptime(thread["created_at"], "%Y-%m-%dT%H:%M:%SZ")
    for j in range(n):
        event_dt = thread_created_dt + timedelta(minutes=random.randint(j * 10, (j + 1) * 60))
        events.append({
            "id":               uid(),
            "thread_id":        thread["id"],
            "customer_id":      thread["customer_id"],
            "company_id":       thread["company_id"],
            "event_type":       random.choice(event_types),
            "actor_type":       random.choice(["user", "machine", "customer"]),
            "actor_id":         random.choice(agent_ids),
            "payload_summary":  None,
            "occurred_at":      event_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
        })

write_csv("raw_thread_events.csv", events)


# ── SLA breaches ──────────────────────────────────────────────────────────────
# First response SLA targets (minutes) by tier
SLA_TARGETS = {"enterprise": 60, "pro": 240, "starter": 1440, "free": None}

sla_breaches = []
for thread in threads:
    target = SLA_TARGETS.get(thread["company_tier"])
    if target is None:
        continue
    frt = thread["first_response_time_mins"]
    if frt and frt > target:
        breach_mins = frt - target
        sla_breaches.append({
            "id":                   uid(),
            "thread_id":            thread["id"],
            "customer_id":          thread["customer_id"],
            "company_id":           thread["company_id"],
            "company_tier":         thread["company_tier"],
            "sla_type":             "first_response_time",
            "target_minutes":       target,
            "actual_minutes":       frt,
            "breach_by_minutes":    breach_mins,
            "priority":             thread["priority"],
            "channel":              thread["channel"],
            "assigned_agent_id":    thread["assigned_agent_id"],
            "assigned_agent_name":  thread["assigned_agent_name"],
            "breached_at":          thread["created_at"],
        })

write_csv("raw_sla_breaches.csv", sla_breaches)

print(f"\n✅  Seed generation complete — {len(companies)} companies, {len(customers)} customers, "
      f"{len(threads)} threads, {len(events)} events, {len(sla_breaches)} SLA breaches")
print(f"    Output directory: {SEED_DIR}")
