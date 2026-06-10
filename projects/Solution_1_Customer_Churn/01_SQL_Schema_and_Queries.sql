-- =============================================================================
-- SOLUTION 1: CUSTOMER CHURN ANALYSIS
-- Star Schema DDL + Data Generation + Analytical Queries
-- Scales to 2M+ rows | SQL Server / PostgreSQL compatible
-- Author: Madhura Pal | Portfolio Project
-- =============================================================================


-- =============================================================================
-- SECTION 1: DIMENSION TABLES (DDL)
-- =============================================================================

-- Date Dimension (pre-built for time intelligence)
CREATE TABLE dim_date (
    date_key        INT           PRIMARY KEY,   -- YYYYMMDD
    full_date       DATE          NOT NULL,
    year            INT           NOT NULL,
    quarter         INT           NOT NULL,
    month_num       INT           NOT NULL,
    month_name      VARCHAR(20)   NOT NULL,
    week_num        INT           NOT NULL,
    day_of_week     VARCHAR(15)   NOT NULL,
    is_weekend      BIT           NOT NULL,
    fiscal_year     INT           NOT NULL,      -- Assumes Apr–Mar fiscal year
    fiscal_quarter  INT           NOT NULL
);

-- Customer Dimension
CREATE TABLE dim_customers (
    customer_key    INT           PRIMARY KEY IDENTITY(1,1),
    customer_id     VARCHAR(20)   NOT NULL UNIQUE,
    first_name      VARCHAR(100)  NOT NULL,
    last_name       VARCHAR(100)  NOT NULL,
    email           VARCHAR(255)  NOT NULL,
    country         VARCHAR(100)  NOT NULL,
    region          VARCHAR(100),
    city            VARCHAR(100),
    signup_date     DATE          NOT NULL,
    age_group       VARCHAR(20)   NOT NULL,   -- '18-24','25-34','35-44','45-54','55+'
    gender          VARCHAR(20),
    acquisition_channel VARCHAR(50) NOT NULL  -- 'Organic','Paid','Referral','Social'
);

-- Product / Plan Dimension
CREATE TABLE dim_plans (
    plan_key        INT           PRIMARY KEY IDENTITY(1,1),
    plan_id         VARCHAR(20)   NOT NULL UNIQUE,
    plan_name       VARCHAR(100)  NOT NULL,   -- 'Starter','Pro','Enterprise'
    billing_cycle   VARCHAR(20)   NOT NULL,   -- 'Monthly','Annual'
    monthly_price   DECIMAL(10,2) NOT NULL,
    annual_price    DECIMAL(10,2),
    tier            VARCHAR(20)   NOT NULL    -- 'Basic','Mid','Premium'
);

-- Segment Dimension
CREATE TABLE dim_segments (
    segment_key     INT           PRIMARY KEY IDENTITY(1,1),
    segment_id      VARCHAR(20)   NOT NULL UNIQUE,
    segment_name    VARCHAR(100)  NOT NULL,   -- 'SMB','Mid-Market','Enterprise'
    industry        VARCHAR(100),
    employee_range  VARCHAR(50)
);


-- =============================================================================
-- SECTION 2: FACT TABLES (DDL)
-- =============================================================================

-- Subscription Fact (one row per subscription lifecycle event)
-- This is the CORE table for churn analysis
CREATE TABLE fact_subscriptions (
    subscription_key    BIGINT        PRIMARY KEY IDENTITY(1,1),
    customer_key        INT           NOT NULL REFERENCES dim_customers(customer_key),
    plan_key            INT           NOT NULL REFERENCES dim_plans(plan_key),
    segment_key         INT           NOT NULL REFERENCES dim_segments(segment_key),
    start_date_key      INT           NOT NULL REFERENCES dim_date(date_key),
    end_date_key        INT           REFERENCES dim_date(date_key),   -- NULL = still active
    status              VARCHAR(20)   NOT NULL,   -- 'Active','Churned','Paused','Upgraded'
    churn_reason        VARCHAR(100),             -- 'Price','Competition','Feature Gap','Support','Unknown'
    mrr                 DECIMAL(12,2) NOT NULL,   -- Monthly Recurring Revenue
    contract_months     INT           NOT NULL,
    is_churned          BIT           NOT NULL DEFAULT 0,
    is_trial            BIT           NOT NULL DEFAULT 0,
    churn_date_key      INT           REFERENCES dim_date(date_key),
    reactivation_flag   BIT           NOT NULL DEFAULT 0
);

-- Monthly Snapshot Fact (enables cohort analysis without complex date logic)
-- Each row = one customer, one month, their state at month-end
CREATE TABLE fact_monthly_customer_snapshot (
    snapshot_key        BIGINT        PRIMARY KEY IDENTITY(1,1),
    customer_key        INT           NOT NULL REFERENCES dim_customers(customer_key),
    plan_key            INT           NOT NULL REFERENCES dim_plans(plan_key),
    segment_key         INT           NOT NULL REFERENCES dim_segments(segment_key),
    snapshot_date_key   INT           NOT NULL REFERENCES dim_date(date_key),
    cohort_date_key     INT           NOT NULL REFERENCES dim_date(date_key),  -- Month of first subscription
    status              VARCHAR(20)   NOT NULL,
    mrr                 DECIMAL(12,2) NOT NULL,
    cumulative_spend    DECIMAL(14,2) NOT NULL,
    support_tickets     INT           NOT NULL DEFAULT 0,
    logins_last_30d     INT           NOT NULL DEFAULT 0,
    feature_usage_score DECIMAL(5,2),  -- 0-100 engagement score
    is_churned          BIT           NOT NULL DEFAULT 0,
    months_since_start  INT           NOT NULL
);


-- =============================================================================
-- SECTION 3: DATE DIMENSION POPULATION
-- =============================================================================

-- Populate dim_date for 2020-01-01 to 2026-12-31
-- (Run this in SQL Server; adapt for PostgreSQL using generate_series)

WITH date_series AS (
    SELECT CAST('2020-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt)
    FROM date_series
    WHERE dt < '2026-12-31'
)
INSERT INTO dim_date (date_key, full_date, year, quarter, month_num, month_name,
                      week_num, day_of_week, is_weekend, fiscal_year, fiscal_quarter)
SELECT
    CAST(FORMAT(dt, 'yyyyMMdd') AS INT),
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    MONTH(dt),
    DATENAME(MONTH, dt),
    DATEPART(WEEK, dt),
    DATENAME(WEEKDAY, dt),
    CASE WHEN DATEPART(WEEKDAY, dt) IN (1,7) THEN 1 ELSE 0 END,
    -- Fiscal Year: Apr=FY start (e.g., Apr 2023 = FY2024)
    CASE WHEN MONTH(dt) >= 4 THEN YEAR(dt) + 1 ELSE YEAR(dt) END,
    CASE
        WHEN MONTH(dt) IN (4,5,6)   THEN 1
        WHEN MONTH(dt) IN (7,8,9)   THEN 2
        WHEN MONTH(dt) IN (10,11,12) THEN 3
        ELSE 4
    END
FROM date_series
OPTION (MAXRECURSION 5000);


-- =============================================================================
-- SECTION 4: SAMPLE DATA GENERATION (scales to 2M+ rows)
-- =============================================================================

-- Plans
INSERT INTO dim_plans (plan_id, plan_name, billing_cycle, monthly_price, annual_price, tier) VALUES
('PLN001', 'Starter Monthly',    'Monthly', 29.00,  NULL,    'Basic'),
('PLN002', 'Starter Annual',     'Annual',  24.00,  288.00,  'Basic'),
('PLN003', 'Pro Monthly',        'Monthly', 99.00,  NULL,    'Mid'),
('PLN004', 'Pro Annual',         'Annual',  79.00,  948.00,  'Mid'),
('PLN005', 'Enterprise Monthly', 'Monthly', 299.00, NULL,    'Premium'),
('PLN006', 'Enterprise Annual',  'Annual',  249.00, 2988.00, 'Premium');

-- Segments
INSERT INTO dim_segments (segment_id, segment_name, industry, employee_range) VALUES
('SEG001', 'SMB',         'Retail',       '1-50'),
('SEG002', 'SMB',         'Technology',   '1-50'),
('SEG003', 'Mid-Market',  'Finance',      '51-500'),
('SEG004', 'Mid-Market',  'Healthcare',   '51-500'),
('SEG005', 'Enterprise',  'Manufacturing','500+'),
('SEG006', 'Enterprise',  'Technology',   '500+');

-- Generate 100,000 customers (repeat pattern to reach 2M+ in fact tables)
-- For production scale: use a numbers/tally table or application-layer seeding

INSERT INTO dim_customers (customer_id, first_name, last_name, email, country, region,
                            city, signup_date, age_group, gender, acquisition_channel)
SELECT
    'CUST' + RIGHT('000000' + CAST(n.num AS VARCHAR), 6),
    first_names.fn,
    last_names.ln,
    'user' + CAST(n.num AS VARCHAR) + '@example.com',
    countries.c,
    regions.r,
    cities.ct,
    DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 1825, '2026-01-01'),  -- Random date in last 5 yrs
    age_groups.ag,
    genders.g,
    channels.ch
FROM
    (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS num FROM sys.objects a, sys.objects b) n
    CROSS APPLY (VALUES ('James'),('Maria'),('David'),('Sarah'),('Michael'),
                        ('Emily'),('Robert'),('Jessica'),('William'),('Lisa')) first_names(fn)
    CROSS APPLY (VALUES ('Smith'),('Johnson'),('Williams'),('Brown'),('Jones')) last_names(ln)
    CROSS APPLY (VALUES ('USA'),('UK'),('Canada'),('Australia'),('India'))    countries(c)
    CROSS APPLY (VALUES ('North'),('South'),('East'),('West'),('Central'))   regions(r)
    CROSS APPLY (VALUES ('New York'),('London'),('Toronto'),('Sydney'),('Mumbai')) cities(ct)
    CROSS APPLY (VALUES ('18-24'),('25-34'),('35-44'),('45-54'),('55+'))     age_groups(ag)
    CROSS APPLY (VALUES ('M'),('F'),('Non-Binary'))                          genders(g)
    CROSS APPLY (VALUES ('Organic'),('Paid'),('Referral'),('Social'))        channels(ch)
WHERE n.num <= 100000;


-- =============================================================================
-- SECTION 5: ANALYTICAL QUERIES (ready for Power BI DirectQuery or import)
-- =============================================================================

-- -----------------------------------------------------------------------
-- Q1: Monthly Churn Rate (Total, by Plan Tier)
-- -----------------------------------------------------------------------
WITH monthly_base AS (
    SELECT
        dd.year,
        dd.month_num,
        dd.month_name,
        dp.tier,
        COUNT(DISTINCT fs.customer_key)  AS total_customers,
        SUM(CASE WHEN fs.is_churned = 1 THEN 1 ELSE 0 END) AS churned_customers
    FROM fact_subscriptions fs
    JOIN dim_date  dd ON fs.start_date_key = dd.date_key
    JOIN dim_plans dp ON fs.plan_key = dp.plan_key
    GROUP BY dd.year, dd.month_num, dd.month_name, dp.tier
)
SELECT
    year,
    month_num,
    month_name,
    tier,
    total_customers,
    churned_customers,
    ROUND(CAST(churned_customers AS FLOAT) / NULLIF(total_customers, 0) * 100, 2) AS churn_rate_pct,
    total_customers - churned_customers AS retained_customers
FROM monthly_base
ORDER BY year, month_num, tier;


-- -----------------------------------------------------------------------
-- Q2: Cohort Retention Analysis (% of original cohort still active each month)
-- -----------------------------------------------------------------------
WITH cohort_base AS (
    SELECT
        cohort_date_key,
        months_since_start,
        COUNT(DISTINCT customer_key)    AS active_customers
    FROM fact_monthly_customer_snapshot
    WHERE is_churned = 0
    GROUP BY cohort_date_key, months_since_start
),
cohort_size AS (
    SELECT cohort_date_key, active_customers AS cohort_total
    FROM cohort_base WHERE months_since_start = 0
)
SELECT
    cb.cohort_date_key,
    dd.year,
    dd.month_name  AS cohort_month,
    cb.months_since_start,
    cb.active_customers,
    cs.cohort_total,
    ROUND(CAST(cb.active_customers AS FLOAT) / NULLIF(cs.cohort_total, 0) * 100, 2) AS retention_pct
FROM cohort_base cb
JOIN cohort_size cs ON cb.cohort_date_key = cs.cohort_date_key
JOIN dim_date    dd ON cb.cohort_date_key = dd.date_key
ORDER BY cb.cohort_date_key, cb.months_since_start;


-- -----------------------------------------------------------------------
-- Q3: Customer Lifetime Value (CLV) by Segment and Acquisition Channel
-- -----------------------------------------------------------------------
SELECT
    dc.acquisition_channel,
    ds.segment_name,
    dp.tier,
    COUNT(DISTINCT dc.customer_key)             AS customer_count,
    AVG(fms.cumulative_spend)                   AS avg_clv,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fms.cumulative_spend)
        OVER (PARTITION BY dc.acquisition_channel, ds.segment_name) AS median_clv,
    AVG(fms.months_since_start)                 AS avg_tenure_months,
    AVG(fms.feature_usage_score)                AS avg_engagement_score
FROM fact_monthly_customer_snapshot fms
JOIN dim_customers dc ON fms.customer_key = dc.customer_key
JOIN dim_segments  ds ON fms.segment_key  = ds.segment_key
JOIN dim_plans     dp ON fms.plan_key     = dp.plan_key
WHERE fms.snapshot_date_key = (SELECT MAX(snapshot_date_key) FROM fact_monthly_customer_snapshot)
GROUP BY dc.acquisition_channel, ds.segment_name, dp.tier, fms.cumulative_spend, fms.months_since_start
ORDER BY avg_clv DESC;


-- -----------------------------------------------------------------------
-- Q4: Churn Reasons Distribution and MRR Impact
-- -----------------------------------------------------------------------
SELECT
    fs.churn_reason,
    dp.tier,
    ds.segment_name,
    COUNT(*)                                    AS churn_count,
    SUM(fs.mrr)                                 AS mrr_lost,
    AVG(fs.mrr)                                 AS avg_mrr_per_churned_customer,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total_churn
FROM fact_subscriptions fs
JOIN dim_plans    dp ON fs.plan_key    = dp.plan_key
JOIN dim_segments ds ON fs.segment_key = ds.segment_key
WHERE fs.is_churned = 1
GROUP BY fs.churn_reason, dp.tier, ds.segment_name
ORDER BY mrr_lost DESC;


-- -----------------------------------------------------------------------
-- Q5: At-Risk Customers (Low Engagement + Approaching Contract End)
-- -----------------------------------------------------------------------
SELECT
    dc.customer_id,
    dc.first_name + ' ' + dc.last_name  AS customer_name,
    dp.plan_name,
    ds.segment_name,
    fms.feature_usage_score,
    fms.logins_last_30d,
    fms.support_tickets,
    fms.mrr,
    fms.cumulative_spend,
    fs.contract_months,
    -- Risk Score: low usage + high tickets + near contract end = high risk
    CASE
        WHEN fms.feature_usage_score < 20 AND fms.support_tickets > 3 THEN 'Critical'
        WHEN fms.feature_usage_score < 40 AND fms.logins_last_30d < 5  THEN 'High'
        WHEN fms.feature_usage_score < 60                               THEN 'Medium'
        ELSE 'Low'
    END AS churn_risk_segment
FROM fact_monthly_customer_snapshot fms
JOIN dim_customers dc ON fms.customer_key = dc.customer_key
JOIN dim_plans     dp ON fms.plan_key     = dp.plan_key
JOIN dim_segments  ds ON fms.segment_key  = ds.segment_key
JOIN fact_subscriptions fs ON fms.customer_key = fs.customer_key AND fs.is_churned = 0
WHERE fms.snapshot_date_key = (SELECT MAX(snapshot_date_key) FROM fact_monthly_customer_snapshot)
  AND fms.is_churned = 0
ORDER BY fms.feature_usage_score ASC, fms.mrr DESC;


-- -----------------------------------------------------------------------
-- Q6: MRR Movement (New, Expansion, Contraction, Churn, Reactivation)
--     Classic SaaS "MRR Waterfall" used by investors
-- -----------------------------------------------------------------------
WITH mrr_current AS (
    SELECT customer_key, snapshot_date_key, mrr, status
    FROM fact_monthly_customer_snapshot
),
mrr_prior AS (
    SELECT customer_key, snapshot_date_key, mrr, status
    FROM fact_monthly_customer_snapshot
),
mrr_movement AS (
    SELECT
        c.snapshot_date_key,
        CASE
            WHEN p.customer_key IS NULL AND c.status = 'Active'   THEN 'New MRR'
            WHEN c.mrr > p.mrr  AND c.status = 'Active'           THEN 'Expansion MRR'
            WHEN c.mrr < p.mrr  AND c.status = 'Active'           THEN 'Contraction MRR'
            WHEN c.is_churned = 1                                  THEN 'Churned MRR'
            WHEN c.status = 'Active' AND p.status = 'Churned'     THEN 'Reactivation MRR'
            ELSE 'Retained MRR'
        END                                        AS mrr_type,
        SUM(c.mrr - ISNULL(p.mrr, 0))             AS mrr_delta,
        COUNT(DISTINCT c.customer_key)             AS customer_count
    FROM mrr_current c
    LEFT JOIN mrr_prior p
        ON c.customer_key = p.customer_key
        AND p.snapshot_date_key = (
            SELECT MAX(snapshot_date_key)
            FROM fact_monthly_customer_snapshot
            WHERE snapshot_date_key < c.snapshot_date_key
            AND customer_key = c.customer_key
        )
    GROUP BY c.snapshot_date_key,
        CASE
            WHEN p.customer_key IS NULL AND c.status = 'Active'   THEN 'New MRR'
            WHEN c.mrr > p.mrr  AND c.status = 'Active'           THEN 'Expansion MRR'
            WHEN c.mrr < p.mrr  AND c.status = 'Active'           THEN 'Contraction MRR'
            WHEN c.is_churned = 1                                  THEN 'Churned MRR'
            WHEN c.status = 'Active' AND p.status = 'Churned'     THEN 'Reactivation MRR'
            ELSE 'Retained MRR'
        END
)
SELECT
    mm.snapshot_date_key,
    dd.year,
    dd.month_name,
    mm.mrr_type,
    mm.mrr_delta,
    mm.customer_count
FROM mrr_movement mm
JOIN dim_date dd ON mm.snapshot_date_key = dd.date_key
ORDER BY mm.snapshot_date_key, mm.mrr_type;
