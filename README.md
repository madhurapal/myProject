# Madhura Pal — Data Analytics Portfolio

> End-to-end analytics projects built for financial services, retail, and fitness verticals.  
> Power BI · SQL · DAX · Python · GitHub Pages  
> 📧 talkmadhura01@gmail.com

---

## Live Dashboards

| Project | Industry | Dataset | Live Link |
|---------|----------|---------|-----------|
| FitCore Customer Churn | Fitness / Retail | 1,047 members | [▶ View Dashboard](https://madhurapal.github.io/myProject/fitcore-churn.html) |
| NovaStar P&L Variance | Financial Services | 2.6M+ rows | [▶ View Dashboard](https://madhurapal.github.io/myProject/pl-variance.html) |
| Streaming Analytics Pipeline | SaaS / Tech | 200K+ rows | [▶ View Dashboard](https://madhurapal.github.io/myProject) |

---

## Project 1 — FitCore Customer Churn Analysis

**Folder:** [`projects/FitCore_Customer_Churn/`](projects/FitCore_Customer_Churn/)

A complete Power BI churn analytics solution for a multi-location fitness gym chain, tracking 1,047 members across 6 locations over 19 months (Oct 2023 – Apr 2025).

### Key Numbers
| Metric | Value |
|--------|-------|
| Total Members | 1,047 |
| Churned Members | 234 |
| Active Members | 813 |
| Churn Rate | 22.3% |
| Monthly Recurring Revenue | $37,397 |

### What Was Built
- **Star schema** with `fact_transactions`, `dim_member`, `dim_location`, `dim_plan`, `dim_date`
- **10 SQL analytical queries** — cohort analysis, plan-level churn, location benchmarking, LTV
- **Power Query M** — 3 transformation queries with custom dim_Date (Oct 2023 – Apr 2025)
- **40+ DAX measures** — Churn Rate, MRR, LTV, NPS, Cohort Retention, At-Risk segmentation
- **5-page HTML dashboard** — dark theme, Chart.js, embedded data constants
- **Power BI build guide** — 13-part step-by-step Word document

### Dashboard Pages
1. Executive Summary — KPI cards, monthly churn trend, churn by location
2. Churn Deep Dive — by plan type, tenure cohort, churn reason breakdown
3. MRR & Revenue — MRR trend, plan mix, revenue at risk
4. Member Segmentation — RFM-style at-risk scoring, active vs churned profile
5. Retention Actions — win-back opportunities, high-risk flagging

### Files
```
FitCore_Customer_Churn/
├── 01_SQL_Schema_and_Queries.sql   ← Star schema DDL + 10 queries
├── 02_PowerQuery_M_Code.m          ← Power Query M transformations
├── 03_DAX_Measures.dax             ← 40+ DAX measures
├── dashboard.html                  ← Interactive 5-page dashboard
├── README.md
├── FitCore_Project_Description.docx
└── data/
    └── FitCore_Churn_Data.xlsx     ← 1,047 member dataset
```

---

## Project 2 — NovaStar Financial Group: P&L Variance Analysis

**Folder:** [`projects/PL_Variance_Analysis/`](projects/PL_Variance_Analysis/)

End-to-end Power BI analytics solution for financial P&L variance reporting, handling **2.63M+ daily transaction rows** across 3 fiscal years. Built for a fictional 60-branch financial services firm spanning 5 US regions.

### Key Numbers
| Metric | Value |
|--------|-------|
| Dataset Size | 2,716,800 rows (2.63M actual + 86K budget) |
| Fiscal Years | FY 2022 – FY 2024 |
| Branches | 60 (5 regions × 12 branches) |
| GL Accounts | 40 accounts across 5 P&L categories |
| 2024 Revenue | $444.2M (+23.3% vs $360.3M budget) |
| 2024 Net Income | $207.7M (+45.0% vs $143.3M budget) |
| 2024 EBITDA Margin | 53.4% |

### What Was Built
- **Star schema** with `fact_actual` (2.63M rows), `fact_budget` (86K rows), `dim_account`, `dim_branch`, `dim_date`
- **10 SQL analytical queries** — P&L waterfall, variance drivers, regional performance, YoY growth, cost-to-income ratio, rolling averages
- **Power Query M** — 5 queries: folder-combine 3 CSV actuals (2.6M rows), budget load, dim_Account, dim_Branch, generated dim_Date
- **40+ DAX measures** — Revenue/EBITDA/NI actual & budget, variance $/%,  YTD, YoY, MoM, rolling 3-month avg, cost-to-income ratio, dynamic labels
- **5-page HTML dashboard** — dark theme, Chart.js, all pre-aggregated data embedded
- **Vectorized numpy generator** — produces full 2.6M row dataset in seconds using broadcasting

### Dashboard Pages
1. Executive P&L — KPI cards, 3-year bar chart, P&L waterfall, full income statement
2. Variance Analysis — Actual vs Budget by category, drivers, variance %
3. Regional Performance — 5-region breakdown with EBITDA margin & cost-to-income
4. Monthly Trends — 36-month revenue line vs budget, EBITDA & NI trend charts
5. Cost Analysis — OpEx donut chart, subcategory breakdown vs budget

### Files
```
PL_Variance_Analysis/
├── 01_SQL_Schema_and_Queries.sql   ← Star schema DDL + 10 analytical queries
├── 02_PowerQuery_M_Code.m          ← Power Query M (5 table queries)
├── 03_DAX_Measures.dax             ← 40+ DAX measures (8 sections)
├── dashboard.html                  ← Interactive 5-page dashboard
├── gen_pl_variance.py              ← Vectorized numpy data generator
├── README.md
└── data/
    ├── actual_2022.csv             ← 876,000 daily rows (23MB)
    ├── actual_2023.csv             ← 876,000 daily rows (23MB)
    ├── actual_2024.csv             ← 878,400 daily rows — leap year (23MB)
    ├── budget_monthly.csv          ← 86,400 monthly budget rows
    └── PL_Dimensions.xlsx          ← dim_account (40 rows) + dim_branch (60 rows)
```

---

## Project 3 — Streaming Analytics Pipeline

**Folder:** [`docs/`](docs/) · [`database/`](database/) · [`connectors/`](connectors/)

Automated end-to-end pipeline: DuckDB → Python → GitHub Actions → HTML Dashboard on GitHub Pages.

### Architecture
```
DuckDB (200K+ rows)
  └── connectors/queries.py        ← Python analytical queries
        └── pipeline/build_dashboard.py  ← Renders HTML
              └── docs/index.html  ← GitHub Pages dashboard
                    └── GitHub Actions  ← Auto-deploys on push
```

### Files
```
database/
├── schema.sql         ← Star + Snowflake DDL (13 tables)
└── seed.py            ← Parameterised data generator (--scale 5 = 1M+ rows)
connectors/
├── db_connector.py    ← DuckDB connection utility
└── queries.py         ← All analytical query functions
pipeline/
└── build_dashboard.py ← Queries DB → renders self-contained HTML
.github/workflows/
└── pipeline.yml       ← seed → build → deploy → notify (Slack + email)
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| BI Tool | Power BI Desktop |
| Database | SQL (star schema), DuckDB |
| Transformations | Power Query M |
| Analytics | DAX (40+ measures per project) |
| Data Generation | Python, NumPy (vectorized) |
| Dashboards | HTML + Chart.js |
| CI/CD | GitHub Actions |
| Hosting | GitHub Pages |
| Documents | Python-docx (Word), OpenPyXL (Excel) |

---

## Resume Alignment

| Resume Bullet | Project |
|--------------|---------|
| Power BI analytics solutions for financial P&L variance reporting, 2M+ rows | NovaStar P&L Variance |
| Customer churn analytics reducing revenue leakage | FitCore Customer Churn |
| Automated data models with Row-Level Security and DAX | Both Power BI projects |
| GitHub portfolio with live dashboards | This repo — github.com/madhurapal/myProject |

---

*Madhura Pal · talkmadhura01@gmail.com · [github.com/madhurapal/myProject](https://github.com/madhurapal/myProject)*
