# FitCore Gym — Customer Churn Analysis

**A full-stack analytics project** built to demonstrate end-to-end data skills: SQL schema design, Excel data modelling, Power Query transformations, and DAX measures — all targeting a real-world business problem at a local fitness company.

---

## Business Context

FitCore Gym operates 6 branches across the city (Downtown, Westside, North Hills, Eastgate, Southpark, Midtown) and offers 4 membership tiers: Basic ($24.99), Standard ($39.99), Premium ($59.99), and Family ($79.99). This project answers one core question:

> **Why are members cancelling, and what can we do about it before they leave?**

---

## Dataset

`data/FitCore_Churn_Data.xlsx` — 3,000 synthetic member records spanning FY2022–FY2026.

| Column | Description |
|---|---|
| Member ID | Unique identifier (FC000001…) |
| Membership Plan | Basic / Standard / Premium / Family |
| Signup Date / Churn Date | Subscription lifecycle dates |
| Tenure Months | How long the member stayed |
| Avg Monthly Visits | Engagement proxy |
| Last Visit Days Ago | Recency signal |
| Satisfaction Score | 1–5 survey rating |
| NPS Score | –100 to +100 net promoter |
| Payment Failures | Count of failed billing attempts |
| Churn Reason | Price / Relocation / Competitor / Dissatisfied / Health / Other |
| Is Churned | Yes / No flag |

---

## Project Structure

```
FitCore_Customer_Churn/
├── data/
│   └── FitCore_Churn_Data.xlsx      # Source data (3,000 members)
├── 01_SQL_Schema_and_Queries.sql    # Star schema DDL + 10 analytical queries
├── 02_PowerQuery_M_Code.m           # Power Query transformations (3 tables)
├── 03_DAX_Measures.dax              # 40+ DAX measures across 10 categories
└── README.md
```

---

## Power BI Model

### Data Model (Star Schema)

```
dim_Date ──────┐
               ├──── fact_subscriptions (one row per member)
Members ───────┘
```

- **Members** — loaded from `Member_Data` sheet, enriched with computed columns (TenureBucket, RiskScore, RiskTier, TotalRevenue)
- **dim_Date** — generated entirely in Power Query, no source file needed
- **Churn_Summary** — pre-aggregated sheet for KPI cards

### Power Query Steps (02_PowerQuery_M_Code.m)

1. Load `Member_Data` from Excel
2. Promote headers, set data types
3. Rename columns (remove spaces for clean DAX references)
4. Add computed columns: `IsChurnedBool`, `TenureBucket`, `RiskScore`, `RiskTier`, `TotalRevenue`, `SignupYearMonth`
5. Generate `dim_Date` table (2022–2026) with Year, Quarter, Month, Week, DayOfWeek, YearMonth, QuarterLabel, DateKey

### DAX Measures (03_DAX_Measures.dax) — 40+ measures across:

| Category | Key Measures |
|---|---|
| Member Counts | Total Members, Active Members, Churned Members |
| Churn Rate | Churn Rate %, Monthly Churn Rate %, 3M Rolling Average |
| Revenue | MRR, ARR, ARPU, LTV (Estimated), Revenue Lost Annualised |
| Tenure & Engagement | Avg Tenure, Avg Monthly Visits, Engagement Score |
| Satisfaction & NPS | Avg Satisfaction, Net Promoter Score, NPS bucket counts |
| At-Risk | High Risk Members, MRR at Risk, At-Risk % |
| Cohort Retention | Cohort Size, Cohort Retained, Cohort Retention % |
| Period Comparisons | MoM Churn Change, MoM MRR Change, YTD Churned |
| Payment Health | Avg Payment Failures, Payment Failure Rate % |
| Dynamic Titles | Selected Plan, Selected Location, Report Subtitle |

---

## Dashboard Pages (recommended layout)

| Page | Visuals |
|---|---|
| **Executive Summary** | KPI cards: Active Members, Churn Rate %, MRR, Avg Satisfaction. Line chart: monthly churn trend. |
| **Churn Drivers** | Bar: churn by reason. Bar: churn by plan. Bar: churn by location. |
| **Engagement Analysis** | Scatter: visits vs churn rate. Bar: tenure bucket vs churn. Column: satisfaction vs churn. |
| **At-Risk Watchlist** | Table: top 100 at-risk active members with Risk Score, Last Visit, Payment Failures. |
| **Cohort Retention** | Matrix heatmap: signup cohort (rows) × tenure milestone (columns) → Retention %. |
| **Revenue Impact** | Waterfall: MRR lost by month. Card: Revenue Lost Annualised. Bar: LTV by plan. |

---

## SQL Queries Reference

| # | Query | Purpose |
|---|---|---|
| 1 | Overall Churn KPIs | KPI card source |
| 2 | Monthly Churn Trend | Line chart |
| 3 | Churn by Plan | Bar chart |
| 4 | Churn by Location | Map / bar |
| 5 | Churn Reasons | Donut chart |
| 6 | Engagement vs Churn | Scatter |
| 7 | At-Risk Watchlist | Table visual |
| 8 | Revenue Impact | Waterfall |
| 9 | Cohort Retention | Heatmap matrix |
| 10 | Demographic Breakdown | Clustered bar |

---

## Key Insights (from the synthetic data)

- **Basic plan** has the highest churn rate — members cite price sensitivity and lack of amenities
- **Members who visit ≤ 4 times/month** churn at 3× the rate of engaged members
- **Churn spikes in January** (New Year's resolutions abandoned) and **August** (seasonal lull)
- **Payment failures** are the single strongest predictor of churn within 60 days
- **Cohort retention** shows a sharp drop at month 3 — the critical intervention window

---

## How to Use

1. Open **Power BI Desktop**
2. **Get Data → Excel** → select `data/FitCore_Churn_Data.xlsx`
3. Open **Power Query Editor** → paste each query from `02_PowerQuery_M_Code.m` into the Advanced Editor
4. Close & Apply
5. Create a blank table called `Measures`, then add each measure from `03_DAX_Measures.dax`
6. Build relationships: `Members[SignupDate]` → `dim_Date[Date]`
7. Build your report pages using the dashboard layout above

---

*Author: Madhura Pal | FY2022–FY2026 | Tool stack: Excel · SQL · Power Query M · DAX · Power BI*
