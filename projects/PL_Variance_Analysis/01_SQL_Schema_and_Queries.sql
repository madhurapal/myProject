-- =============================================================================
-- NovaStar Financial Group — P&L Variance Analysis
-- Star Schema DDL + 10 Analytical Queries
-- Data: 60 branches × 40 accounts × 3 years (2022-2024) ≈ 2.6M actual rows
-- =============================================================================

-- ── DIMENSION TABLES ──────────────────────────────────────────────────────────

CREATE TABLE dim_account (
    account_id    INTEGER       PRIMARY KEY,
    account_code  VARCHAR(8)    NOT NULL,
    account_name  VARCHAR(60)   NOT NULL,
    category      VARCHAR(20)   NOT NULL,  -- Revenue / Provision / OpEx / D&A / Tax
    subcategory   VARCHAR(30)   NOT NULL,
    p_l_sign      SMALLINT      NOT NULL   -- 1=Income, -1=Expense
);

CREATE TABLE dim_branch (
    branch_id    VARCHAR(4)    PRIMARY KEY,  -- B001-B060
    branch_name  VARCHAR(40)   NOT NULL,
    region       VARCHAR(15)   NOT NULL,     -- Northeast / Southeast / Midwest / Southwest / West
    city         VARCHAR(25)   NOT NULL,
    branch_type  VARCHAR(20)   NOT NULL,     -- Corporate Hub / Regional Office / Standard / Digital
    opened_year  SMALLINT      NOT NULL
);

CREATE TABLE dim_date (
    date_key     DATE          PRIMARY KEY,
    year         SMALLINT      NOT NULL,
    quarter      VARCHAR(2)    NOT NULL,  -- Q1-Q4
    month        SMALLINT      NOT NULL,
    month_name   VARCHAR(10)   NOT NULL,
    year_month   VARCHAR(7)    NOT NULL,  -- 2024-03
    day_of_week  VARCHAR(10)   NOT NULL,
    is_weekend   BOOLEAN       NOT NULL,
    is_month_end BOOLEAN       NOT NULL
);

-- Populate dim_date
INSERT INTO dim_date
SELECT
    d::DATE                                                     AS date_key,
    EXTRACT(YEAR FROM d)::SMALLINT                              AS year,
    'Q' || EXTRACT(QUARTER FROM d)::VARCHAR                    AS quarter,
    EXTRACT(MONTH FROM d)::SMALLINT                            AS month,
    TO_CHAR(d, 'Mon')                                          AS month_name,
    TO_CHAR(d, 'YYYY-MM')                                      AS year_month,
    TO_CHAR(d, 'Day')                                          AS day_of_week,
    EXTRACT(DOW FROM d) IN (0, 6)                              AS is_weekend,
    d = DATE_TRUNC('month', d) + INTERVAL '1 month' - INTERVAL '1 day' AS is_month_end
FROM GENERATE_SERIES('2022-01-01'::DATE, '2024-12-31'::DATE, '1 day') AS gs(d);

-- ── FACT TABLES ────────────────────────────────────────────────────────────────

-- Daily actual transactions (2.6M rows — loaded from 3 CSV files)
CREATE TABLE fact_actual (
    date        DATE          NOT NULL,
    branch_id   VARCHAR(4)    NOT NULL,
    account_id  INTEGER       NOT NULL,
    amount      NUMERIC(14,2) NOT NULL,   -- signed: Revenue positive, Costs negative
    FOREIGN KEY (date)       REFERENCES dim_date(date_key),
    FOREIGN KEY (branch_id)  REFERENCES dim_branch(branch_id),
    FOREIGN KEY (account_id) REFERENCES dim_account(account_id)
);

-- Monthly budget (86K rows — loaded from budget_monthly.csv)
CREATE TABLE fact_budget (
    period      VARCHAR(7)    NOT NULL,  -- 2024-03
    year        SMALLINT      NOT NULL,
    month       SMALLINT      NOT NULL,
    branch_id   VARCHAR(4)    NOT NULL,
    account_id  INTEGER       NOT NULL,
    budget_amount NUMERIC(14,2) NOT NULL,
    FOREIGN KEY (branch_id)  REFERENCES dim_branch(branch_id),
    FOREIGN KEY (account_id) REFERENCES dim_account(account_id)
);

-- Load data (adjust paths as needed)
-- COPY fact_actual FROM 'actual_2022.csv' CSV HEADER;
-- COPY fact_actual FROM 'actual_2023.csv' CSV HEADER;
-- COPY fact_actual FROM 'actual_2024.csv' CSV HEADER;
-- COPY fact_budget FROM 'budget_monthly.csv' CSV HEADER;


-- =============================================================================
-- ANALYTICAL QUERIES
-- =============================================================================

-- ── Q1: Annual P&L Summary (Actual vs Budget) ─────────────────────────────────
SELECT
    d.year,
    a.category,
    ROUND(SUM(fa.amount)         / 1e6, 2)  AS actual_mm,
    ROUND(SUM(fb.budget_amount)  / 1e6, 2)  AS budget_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / 1e6, 2) AS variance_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / ABS(NULLIF(SUM(fb.budget_amount),0)) * 100, 1) AS variance_pct
FROM fact_actual fa
JOIN dim_date    d  ON fa.date       = d.date_key
JOIN dim_account a  ON fa.account_id = a.account_id
JOIN fact_budget fb ON fa.account_id = fb.account_id
                    AND fb.year      = d.year
                    AND fb.month     = d.month
                    AND fb.branch_id = fa.branch_id
GROUP BY d.year, a.category
ORDER BY d.year, a.category;


-- ── Q2: Monthly Revenue Trend (Actual vs Budget) ──────────────────────────────
SELECT
    d.year_month,
    d.year,
    d.month,
    ROUND(SUM(fa.amount)       / 1e6, 2) AS actual_revenue_mm,
    ROUND(SUM(fb.budget_amount)/ 1e6, 2) AS budget_revenue_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / 1e6, 2) AS variance_mm
FROM fact_actual fa
JOIN dim_date    d  ON fa.date       = d.date_key
JOIN dim_account a  ON fa.account_id = a.account_id
JOIN fact_budget fb ON fa.account_id = fb.account_id
                    AND fb.year = d.year AND fb.month = d.month
                    AND fb.branch_id = fa.branch_id
WHERE a.category = 'Revenue'
GROUP BY d.year_month, d.year, d.month
ORDER BY d.year_month;


-- ── Q3: P&L Waterfall — Key Lines (2024 Actual) ───────────────────────────────
WITH pl AS (
    SELECT
        a.category,
        SUM(fa.amount) AS total_amount
    FROM fact_actual fa
    JOIN dim_date    d ON fa.date = d.date_key
    JOIN dim_account a ON fa.account_id = a.account_id
    WHERE d.year = 2024
    GROUP BY a.category
)
SELECT
    category,
    ROUND(total_amount / 1e6, 1) AS actual_mm,
    CASE category
        WHEN 'Revenue'   THEN 1
        WHEN 'Provision' THEN 2
        WHEN 'OpEx'      THEN 3
        WHEN 'D&A'       THEN 4
        WHEN 'Tax'       THEN 5
    END AS sort_order
FROM pl
UNION ALL
SELECT 'Net Revenue',
       ROUND((SELECT SUM(amount)/1e6 FROM fact_actual fa JOIN dim_date d ON fa.date=d.date_key JOIN dim_account a ON fa.account_id=a.account_id WHERE d.year=2024 AND a.category IN ('Revenue','Provision')), 1),
       1.5
UNION ALL
SELECT 'EBITDA',
       ROUND((SELECT SUM(amount)/1e6 FROM fact_actual fa JOIN dim_date d ON fa.date=d.date_key JOIN dim_account a ON fa.account_id=a.account_id WHERE d.year=2024 AND a.category IN ('Revenue','Provision','OpEx')), 1),
       3.5
UNION ALL
SELECT 'Pre-Tax Income',
       ROUND((SELECT SUM(amount)/1e6 FROM fact_actual fa JOIN dim_date d ON fa.date=d.date_key JOIN dim_account a ON fa.account_id=a.account_id WHERE d.year=2024 AND a.category IN ('Revenue','Provision','OpEx','D&A')), 1),
       4.5
ORDER BY sort_order;


-- ── Q4: Variance Analysis by Account (2024 — top drivers) ────────────────────
SELECT
    a.account_code,
    a.account_name,
    a.category,
    a.subcategory,
    ROUND(SUM(fa.amount)         / 1e6, 3) AS actual_mm,
    ROUND(SUM(fb.budget_amount)  / 1e6, 3) AS budget_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / 1e6, 3) AS variance_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / ABS(NULLIF(SUM(fb.budget_amount),0)) * 100, 1) AS variance_pct
FROM fact_actual fa
JOIN dim_date    d  ON fa.date       = d.date_key
JOIN dim_account a  ON fa.account_id = a.account_id
JOIN fact_budget fb ON fa.account_id = fb.account_id
                    AND fb.year = d.year AND fb.month = d.month
                    AND fb.branch_id = fa.branch_id
WHERE d.year = 2024
GROUP BY a.account_code, a.account_name, a.category, a.subcategory
ORDER BY ABS(SUM(fa.amount) - SUM(fb.budget_amount)) DESC
LIMIT 15;


-- ── Q5: Regional P&L Performance (2024) ───────────────────────────────────────
SELECT
    b.region,
    a.category,
    ROUND(SUM(fa.amount)         / 1e6, 2) AS actual_mm,
    ROUND(SUM(fb.budget_amount)  / 1e6, 2) AS budget_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / 1e6, 2) AS variance_mm
FROM fact_actual fa
JOIN dim_date    d  ON fa.date       = d.date_key
JOIN dim_branch  b  ON fa.branch_id  = b.branch_id
JOIN dim_account a  ON fa.account_id = a.account_id
JOIN fact_budget fb ON fa.account_id = fb.account_id
                    AND fb.branch_id = fa.branch_id
                    AND fb.year = d.year AND fb.month = d.month
WHERE d.year = 2024
GROUP BY b.region, a.category
ORDER BY b.region, a.category;


-- ── Q6: Net Income by Region and Branch Type (2024) ───────────────────────────
SELECT
    b.region,
    b.branch_type,
    COUNT(DISTINCT fa.branch_id)              AS branch_count,
    ROUND(SUM(fa.amount) / 1e6, 2)           AS total_net_income_mm,
    ROUND(SUM(fa.amount) / COUNT(DISTINCT fa.branch_id) / 1e6, 3) AS ni_per_branch_mm
FROM fact_actual fa
JOIN dim_date    d ON fa.date       = d.date_key
JOIN dim_branch  b ON fa.branch_id  = b.branch_id
WHERE d.year = 2024
GROUP BY b.region, b.branch_type
ORDER BY total_net_income_mm DESC;


-- ── Q7: Cost-to-Income Ratio by Region (2024) ─────────────────────────────────
WITH income AS (
    SELECT b.region, SUM(fa.amount) AS total_income
    FROM fact_actual fa
    JOIN dim_date d ON fa.date=d.date_key
    JOIN dim_branch b ON fa.branch_id=b.branch_id
    JOIN dim_account a ON fa.account_id=a.account_id
    WHERE d.year=2024 AND a.category='Revenue'
    GROUP BY b.region
),
costs AS (
    SELECT b.region, SUM(fa.amount) AS total_costs
    FROM fact_actual fa
    JOIN dim_date d ON fa.date=d.date_key
    JOIN dim_branch b ON fa.branch_id=b.branch_id
    JOIN dim_account a ON fa.account_id=a.account_id
    WHERE d.year=2024 AND a.category='OpEx'
    GROUP BY b.region
)
SELECT
    i.region,
    ROUND(i.total_income / 1e6, 1)             AS revenue_mm,
    ROUND(ABS(c.total_costs) / 1e6, 1)         AS opex_mm,
    ROUND(ABS(c.total_costs) / i.total_income * 100, 1) AS cost_to_income_ratio_pct
FROM income i
JOIN costs c ON i.region = c.region
ORDER BY cost_to_income_ratio_pct;


-- ── Q8: Year-over-Year Growth by P&L Category ─────────────────────────────────
WITH annual AS (
    SELECT
        d.year,
        a.category,
        SUM(fa.amount) AS total
    FROM fact_actual fa
    JOIN dim_date d ON fa.date=d.date_key
    JOIN dim_account a ON fa.account_id=a.account_id
    GROUP BY d.year, a.category
)
SELECT
    curr.year,
    curr.category,
    ROUND(curr.total / 1e6, 1)              AS current_mm,
    ROUND(prev.total / 1e6, 1)              AS prior_mm,
    ROUND((curr.total - prev.total) / ABS(NULLIF(prev.total,0)) * 100, 1) AS yoy_growth_pct
FROM annual curr
LEFT JOIN annual prev ON prev.year = curr.year - 1 AND prev.category = curr.category
WHERE curr.year IN (2023, 2024)
ORDER BY curr.year, curr.category;


-- ── Q9: OpEx Breakdown — Subcategory Drill-Down (2024) ────────────────────────
SELECT
    a.subcategory,
    ROUND(SUM(fa.amount)         / 1e6, 2) AS actual_mm,
    ROUND(SUM(fb.budget_amount)  / 1e6, 2) AS budget_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / 1e6, 2) AS variance_mm,
    ROUND((SUM(fa.amount) - SUM(fb.budget_amount)) / ABS(NULLIF(SUM(fb.budget_amount),0)) * 100, 1) AS variance_pct,
    ROUND(ABS(SUM(fa.amount)) / (
        SELECT ABS(SUM(fa2.amount)) FROM fact_actual fa2
        JOIN dim_date d2 ON fa2.date=d2.date_key
        JOIN dim_account a2 ON fa2.account_id=a2.account_id
        WHERE d2.year=2024 AND a2.category='OpEx'
    ) * 100, 1) AS pct_of_total_opex
FROM fact_actual fa
JOIN dim_date    d  ON fa.date       = d.date_key
JOIN dim_account a  ON fa.account_id = a.account_id
JOIN fact_budget fb ON fa.account_id = fb.account_id
                    AND fb.year = d.year AND fb.month = d.month
                    AND fb.branch_id = fa.branch_id
WHERE d.year = 2024 AND a.category = 'OpEx'
GROUP BY a.subcategory
ORDER BY SUM(fa.amount);


-- ── Q10: Rolling 3-Month Revenue vs Budget (Moving Average) ───────────────────
WITH monthly AS (
    SELECT
        d.year_month,
        d.year,
        d.month,
        SUM(CASE WHEN a.category='Revenue' THEN fa.amount ELSE 0 END) AS actual_rev,
        SUM(CASE WHEN a.category='Revenue' THEN fb.budget_amount ELSE 0 END) AS budget_rev
    FROM fact_actual fa
    JOIN dim_date    d  ON fa.date=d.date_key
    JOIN dim_account a  ON fa.account_id=a.account_id
    JOIN fact_budget fb ON fa.account_id=fb.account_id
                        AND fb.year=d.year AND fb.month=d.month
                        AND fb.branch_id=fa.branch_id
    GROUP BY d.year_month, d.year, d.month
)
SELECT
    year_month,
    ROUND(actual_rev / 1e6, 2)                  AS actual_rev_mm,
    ROUND(budget_rev / 1e6, 2)                  AS budget_rev_mm,
    ROUND(AVG(actual_rev) OVER (
        ORDER BY year_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) / 1e6, 2)                                 AS rolling_3m_avg_mm,
    ROUND((actual_rev - budget_rev) / ABS(NULLIF(budget_rev,0)) * 100, 1) AS monthly_var_pct
FROM monthly
ORDER BY year_month;
