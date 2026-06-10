# Power BI Analytics Portfolio

End-to-end analytics pipeline: **DuckDB → Python → GitHub Actions → HTML Dashboard on GitHub Pages**

**Live Dashboard:** https://madhurapal.github.io/myProject

---

## Architecture

```
Source (DuckDB)
    │
    ├── database/schema.sql        ← Star + Snowflake schema DDL
    └── database/seed.py           ← Generates 200K+ realistic rows
          │
          ▼
connectors/
    ├── db_connector.py            ← DuckDB connection utility
    └── queries.py                 ← All analytical queries → DataFrames
          │
          ▼
pipeline/
    └── build_dashboard.py         ← Queries DB → renders HTML dashboard
          │
          ▼
docs/index.html                    ← Self-contained HTML dashboard (Chart.js)
          │
          ▼
.github/workflows/pipeline.yml     ← GitHub Actions: seed → build → deploy → notify
          │
          ▼
GitHub Pages → Live URL
```

---

## Solutions

### Solution 1: Customer Churn Analysis
Star schema. Tracks subscriber lifecycle and monthly engagement snapshots.

**KPIs:** Monthly Churn Rate, Annualised Churn, Net MRR, ARR, Net Retention Rate, Cohort Retention Heatmap, CLV, At-Risk Segmentation

### Solution 2: Financial P&L Variance + Supply Chain KPIs
Snowflake schema. Blends Actual + Budget GL entries with sales orders and inventory.

**Finance KPIs:** Actual vs Budget Variance, Gross Margin %, EBITDA Margin, Revenue Trend

**Supply Chain KPIs:** OTIF Rate, On-Time Delivery, Inventory Health, Days of Supply, Supplier Scorecard

---

## Quick Start (Local)

### 1. Install Python dependencies
```bash
pip install -r requirements.txt
```

### 2. Seed the database
```bash
python database/seed.py
# Generates analytics.duckdb with ~200K rows

# For larger dataset (1M+ rows):
python database/seed.py --scale 5

# Reset and reseed:
python database/seed.py --reset
```

### 3. Build the dashboard
```bash
python pipeline/build_dashboard.py
# Writes: docs/index.html
```

### 4. Open the dashboard
```bash
open docs/index.html      # macOS
start docs/index.html     # Windows
xdg-open docs/index.html  # Linux
```

### 5. Verify database connection
```bash
python connectors/db_connector.py
# Prints row counts for all tables
```

---

## GitHub Actions Pipeline

The pipeline runs automatically on:
- Every push to `main` that touches `database/`, `connectors/`, or `pipeline/`
- Every Monday at 06:00 UTC (weekly refresh)
- Manual trigger via Actions tab

### Pipeline Steps

| Job | What it does |
|-----|-------------|
| `seed` | Installs deps, runs `seed.py`, uploads `analytics.duckdb` as artifact |
| `build` | Downloads DB artifact, runs `build_dashboard.py`, uploads `docs/` artifact |
| `deploy` | Deploys `docs/` to GitHub Pages |
| `notify` | Sends Slack + email report with pipeline status and dashboard URL |

### Setup: Enable GitHub Pages

1. Go to repo **Settings → Pages**
2. Set Source to **GitHub Actions**
3. Push to `main` — pipeline deploys automatically

### Setup: Notifications (Optional)

Add these secrets in **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL (free) |
| `GMAIL_USER` | Your Gmail address |
| `GMAIL_APP_PASSWORD` | Gmail App Password (not your regular password) |
| `NOTIFY_EMAIL` | Email to receive reports (defaults to `GMAIL_USER`) |

**Get Gmail App Password:** myaccount.google.com → Security → 2-Step Verification → App passwords

---

## File Structure

```
myProject/
├── .github/
│   └── workflows/
│       └── pipeline.yml              ← GitHub Actions workflow
├── database/
│   ├── schema.sql                    ← DuckDB DDL (all 13 tables)
│   └── seed.py                       ← Data generation script
├── connectors/
│   ├── db_connector.py               ← Connection utility
│   └── queries.py                    ← Analytical query functions
├── pipeline/
│   └── build_dashboard.py            ← Dashboard renderer
├── docs/
│   └── index.html                    ← Generated dashboard (gitignored source, published to Pages)
├── Solution_1_Customer_Churn/        ← Original Power BI files
│   ├── 01_SQL_Schema_and_Queries.sql
│   ├── 02_PowerQuery_M_Code.m
│   └── 03_DAX_Measures.dax
├── Solution_2_Financial_SupplyChain/
│   ├── 01_SQL_Schema_and_Queries.sql
│   ├── 02_PowerQuery_M_Code.m
│   └── 03_DAX_Measures.dax
├── Portfolio_Architecture_Guide.docx ← Architecture and recruiter guide
├── requirements.txt
└── README.md
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Database | DuckDB | Zero-install, columnar analytics engine, runs in GitHub Actions |
| Connector | Python + duckdb-python | Single `pip install`, full SQL support |
| Queries | pandas DataFrames | Standard analytics interface |
| Dashboard | Chart.js (CDN) | No build step, fully self-contained HTML |
| CI/CD | GitHub Actions | Free for public repos, built-in Pages deployment |
| Hosting | GitHub Pages | Free, auto-deploys on push |
| Notifications | Slack webhook + Gmail SMTP | Free tiers, zero infrastructure |

---

## Interview Talking Points

- **"I chose DuckDB because it runs in-process with zero infrastructure cost — the same code that runs on my laptop runs identically in GitHub Actions."**
- **"The pipeline is fully declarative — a schema change triggers an automatic reseed, rebuild, and redeploy without any manual steps."**
- **"The HTML dashboard is 100% self-contained — no server, no API calls, all data embedded as JSON at build time. It loads in under 100ms."**
- **"The seed script is parameterised with a scale factor — `--scale 5` generates 1M+ rows without changing a single query."**
- **"I separated concerns cleanly: schema DDL, seed logic, query functions, and rendering are all independent — any layer can be swapped without touching the others."**

---

*Author: Madhura Pal | talkmadhura01@gmail.com | github.com/madhurapal/myProject*
