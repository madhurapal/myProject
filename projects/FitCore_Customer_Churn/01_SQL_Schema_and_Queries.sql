-- =============================================================================
-- FitCore Gym — Customer Churn Analysis
-- SQL Schema + Analytical Queries
-- Author  : Madhura Pal
-- Context : Local fitness company with 6 locations, 4 membership tiers
--           Data range: FY2022 – FY2026
-- =============================================================================


-- =============================================================================
-- SECTION 1: SCHEMA DEFINITION (Star Schema)
-- =============================================================================

-- Dimension: Date
CREATE TABLE dim_date (
    date_key        INT         PRIMARY KEY,   -- YYYYMMDD
    full_date       DATE        NOT NULL,
    year            INT,
    quarter         INT,
    month_num       INT,
    month_name      VARCHAR(12),
    week_num        INT,
    day_of_week     VARCHAR(10),
    is_weekend      BOOLEAN,
    fiscal_year     INT,
    fiscal_quarter  INT,
    year_month      VARCHAR(7)  -- 'YYYY-MM'
);

-- Dimension: Members
CREATE TABLE dim_members (
    member_key          INT         PRIMARY KEY,
    member_id           VARCHAR(10) UNIQUE NOT NULL,   -- FC000001
    full_name           VARCHAR(100),
    age_group           VARCHAR(10),
    gender              VARCHAR(20),
    state               VARCHAR(5),
    home_location       VARCHAR(30),
    referral_source     VARCHAR(30),
    has_personal_trainer BOOLEAN,
    favourite_class     VARCHAR(30)
);

-- Dimension: Membership Plans
CREATE TABLE dim_plans (
    plan_key        INT         PRIMARY KEY,
    plan_name       VARCHAR(20) NOT NULL,   -- Basic / Standard / Premium / Family
    monthly_fee     DECIMAL(6,2),
    service_type    VARCHAR(30),            -- Gym Only, Gym + Classes, Full Access
    tier            VARCHAR(10)             -- Entry / Mid / Premium
);

-- Dimension: Locations
CREATE TABLE dim_locations (
    location_key    INT         PRIMARY KEY,
    location_name   VARCHAR(30) NOT NULL,
    city            VARCHAR(30),
    state           VARCHAR(5),
    capacity        INT,
    opened_date     DATE,
    has_pool        BOOLEAN,
    has_sauna       BOOLEAN,
    sq_footage      INT
);

-- Fact: Subscriptions (one row per member, tracks lifecycle)
CREATE TABLE fact_subscriptions (
    subscription_key    INT         PRIMARY KEY,
    member_key          INT         REFERENCES dim_members(member_key),
    plan_key            INT         REFERENCES dim_plans(plan_key),
    location_key        INT         REFERENCES dim_locations(location_key),
    signup_date_key     INT         REFERENCES dim_date(date_key),
    churn_date_key      INT         REFERENCES dim_date(date_key),
    tenure_months       INT,
    status              VARCHAR(10),   -- Active / Churned
    churn_reason        VARCHAR(50),
    monthly_fee         DECIMAL(6,2),
    total_revenue       DECIMAL(10,2),
    satisfaction_score  INT,           -- 1-5
    nps_score           INT,
    payment_failures    INT,
    avg_monthly_visits  INT,
    last_visit_days_ago INT
);

-- Fact: Monthly Visits (one row per member per month)
CREATE TABLE fact_monthly_visits (
    visit_key           INT         PRIMARY KEY,
    member_key          INT         REFERENCES dim_members(member_key),
    location_key        INT         REFERENCES dim_locations(location_key),
    date_key            INT         REFERENCES dim_date(date_key),
    year                INT,
    month               INT,
    total_visits        INT,
    class_bookings      INT,
    pt_sessions         INT,
    avg_visit_minutes   INT,
    peak_hour           VARCHAR(15)
);

-- Fact: Payments
CREATE TABLE fact_payments (
    payment_key         INT         PRIMARY KEY,
    member_key          INT         REFERENCES dim_members(member_key),
    location_key        INT         REFERENCES dim_locations(location_key),
    date_key            INT         REFERENCES dim_date(date_key),
    amount              DECIMAL(6,2),
    status              VARCHAR(15),   -- Collected / Failed
    failure_reason      VARCHAR(50)
);


-- =============================================================================
-- SECTION 2: ANALYTICAL QUERIES (Power BI Import Layer)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Query 1: Overall Churn KPIs
-- Purpose : KPI cards on main dashboard page
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                AS Total_Members,
    SUM(CASE WHEN status = 'Active'  THEN 1 ELSE 0 END)   AS Active_Members,
    SUM(CASE WHEN status = 'Churned' THEN 1 ELSE 0 END)   AS Churned_Members,
    ROUND(
        SUM(CASE WHEN status = 'Churned' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                       AS Churn_Rate_Pct,
    SUM(CASE WHEN status = 'Active' THEN monthly_fee ELSE 0 END) AS Monthly_Recurring_Revenue,
    ROUND(AVG(tenure_months), 1)                           AS Avg_Tenure_Months,
    ROUND(AVG(CAST(satisfaction_score AS FLOAT)), 2)       AS Avg_Satisfaction_Score,
    ROUND(AVG(CAST(nps_score AS FLOAT)), 1)                AS Avg_NPS_Score
FROM fact_subscriptions;


-- -----------------------------------------------------------------------------
-- Query 2: Monthly Churn Trend
-- Purpose : Line chart — churn count and rate by month
-- -----------------------------------------------------------------------------
SELECT
    d.year_month                                            AS Period,
    d.year                                                  AS Year,
    d.month_num                                             AS Month_Num,
    d.month_name                                            AS Month_Name,
    COUNT(fs.subscription_key)                              AS Churned_Count,
    ROUND(
        COUNT(fs.subscription_key) * 100.0 /
        NULLIF((SELECT COUNT(*) FROM fact_subscriptions
                WHERE signup_date_key <= d.date_key), 0), 2
    )                                                       AS Monthly_Churn_Rate_Pct
FROM fact_subscriptions fs
JOIN dim_date d ON fs.churn_date_key = d.date_key
WHERE fs.status = 'Churned'
GROUP BY d.year_month, d.year, d.month_num, d.month_name, d.date_key
ORDER BY d.year, d.month_num;


-- -----------------------------------------------------------------------------
-- Query 3: Churn by Membership Plan
-- Purpose : Bar chart — which plan has highest churn
-- -----------------------------------------------------------------------------
SELECT
    p.plan_name,
    p.monthly_fee,
    p.service_type,
    COUNT(fs.subscription_key)                              AS Total_Members,
    SUM(CASE WHEN fs.status = 'Churned' THEN 1 ELSE 0 END) AS Churned,
    SUM(CASE WHEN fs.status = 'Active'  THEN 1 ELSE 0 END) AS Active,
    ROUND(
        SUM(CASE WHEN fs.status = 'Churned' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                       AS Churn_Rate_Pct,
    SUM(CASE WHEN fs.status = 'Active' THEN fs.monthly_fee ELSE 0 END)
                                                            AS Active_MRR,
    ROUND(AVG(fs.tenure_months), 1)                        AS Avg_Tenure_Months,
    ROUND(AVG(CAST(fs.satisfaction_score AS FLOAT)), 2)    AS Avg_Satisfaction
FROM fact_subscriptions fs
JOIN dim_plans p ON fs.plan_key = p.plan_key
GROUP BY p.plan_name, p.monthly_fee, p.service_type
ORDER BY Churn_Rate_Pct DESC;


-- -----------------------------------------------------------------------------
-- Query 4: Churn by Location
-- Purpose : Map / bar chart — which gym branch has highest churn
-- -----------------------------------------------------------------------------
SELECT
    l.location_name,
    l.state,
    COUNT(fs.subscription_key)                              AS Total_Members,
    SUM(CASE WHEN fs.status = 'Churned' THEN 1 ELSE 0 END) AS Churned,
    ROUND(
        SUM(CASE WHEN fs.status = 'Churned' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                       AS Churn_Rate_Pct,
    ROUND(AVG(CAST(fs.avg_monthly_visits AS FLOAT)), 1)    AS Avg_Monthly_Visits,
    ROUND(AVG(CAST(fs.satisfaction_score AS FLOAT)), 2)    AS Avg_Satisfaction,
    SUM(CASE WHEN fs.status='Active' THEN fs.monthly_fee ELSE 0 END)
                                                            AS Location_MRR
FROM fact_subscriptions fs
JOIN dim_locations l ON fs.location_key = l.location_key
GROUP BY l.location_name, l.state
ORDER BY Churn_Rate_Pct DESC;


-- -----------------------------------------------------------------------------
-- Query 5: Churn Reasons Analysis
-- Purpose : Donut / bar chart — why members are leaving
-- -----------------------------------------------------------------------------
SELECT
    fs.churn_reason,
    COUNT(*)                                                AS Churned_Count,
    ROUND(COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM fact_subscriptions WHERE status='Churned'), 1)
                                                            AS Pct_of_Total_Churn,
    ROUND(AVG(fs.tenure_months), 1)                        AS Avg_Tenure_At_Churn,
    ROUND(AVG(CAST(fs.satisfaction_score AS FLOAT)), 2)    AS Avg_Satisfaction,
    ROUND(AVG(CAST(fs.monthly_fee AS FLOAT)), 2)           AS Avg_Fee,
    SUM(fs.monthly_fee)                                     AS Revenue_Lost_Monthly
FROM fact_subscriptions fs
WHERE fs.status = 'Churned'
  AND fs.churn_reason IS NOT NULL
GROUP BY fs.churn_reason
ORDER BY Churned_Count DESC;


-- -----------------------------------------------------------------------------
-- Query 6: Engagement vs Churn (Visits Correlation)
-- Purpose : Scatter chart — low visit frequency = higher churn risk
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN avg_monthly_visits = 0      THEN '0 visits'
        WHEN avg_monthly_visits <= 4     THEN '1–4 visits'
        WHEN avg_monthly_visits <= 8     THEN '5–8 visits'
        WHEN avg_monthly_visits <= 12    THEN '9–12 visits'
        ELSE '13+ visits'
    END                                                     AS Visit_Frequency_Band,
    COUNT(*)                                                AS Total_Members,
    SUM(CASE WHEN status='Churned' THEN 1 ELSE 0 END)      AS Churned,
    ROUND(
        SUM(CASE WHEN status='Churned' THEN 1 ELSE 0 END)*100.0/COUNT(*),1
    )                                                       AS Churn_Rate_Pct,
    ROUND(AVG(CAST(satisfaction_score AS FLOAT)),2)        AS Avg_Satisfaction
FROM fact_subscriptions
GROUP BY Visit_Frequency_Band
ORDER BY Churn_Rate_Pct DESC;


-- -----------------------------------------------------------------------------
-- Query 7: At-Risk Member Watchlist
-- Purpose : Table visual — members likely to churn next 60 days
-- -----------------------------------------------------------------------------
SELECT
    m.member_id,
    m.full_name,
    m.home_location,
    p.plan_name,
    fs.monthly_fee,
    fs.tenure_months,
    fs.avg_monthly_visits,
    fs.last_visit_days_ago,
    fs.satisfaction_score,
    fs.nps_score,
    fs.payment_failures,
    -- Risk score: higher = more at risk
    (
        CASE WHEN fs.last_visit_days_ago > 30  THEN 2 ELSE 0 END +
        CASE WHEN fs.satisfaction_score <= 2   THEN 3 ELSE 0 END +
        CASE WHEN fs.nps_score < 0             THEN 2 ELSE 0 END +
        CASE WHEN fs.payment_failures > 1      THEN 2 ELSE 0 END +
        CASE WHEN fs.avg_monthly_visits <= 2   THEN 1 ELSE 0 END
    )                                                       AS Risk_Score
FROM fact_subscriptions fs
JOIN dim_members m  ON fs.member_key  = m.member_key
JOIN dim_plans   p  ON fs.plan_key    = p.plan_key
WHERE fs.status = 'Active'
  AND (
    fs.last_visit_days_ago > 30     OR
    fs.satisfaction_score  <= 2     OR
    fs.nps_score           < 0      OR
    fs.payment_failures    > 1
  )
ORDER BY Risk_Score DESC, fs.monthly_fee DESC
LIMIT 200;


-- -----------------------------------------------------------------------------
-- Query 8: Revenue Impact of Churn
-- Purpose : Revenue waterfall — what churn costs per month
-- -----------------------------------------------------------------------------
SELECT
    d.year                                                  AS Year,
    d.month_num                                             AS Month,
    d.month_name                                            AS Month_Name,
    COUNT(fs.subscription_key)                              AS Members_Churned,
    SUM(fs.monthly_fee)                                     AS MRR_Lost,
    SUM(fs.total_revenue)                                   AS LTV_Lost,
    ROUND(AVG(fs.tenure_months),1)                         AS Avg_Tenure_Lost
FROM fact_subscriptions fs
JOIN dim_date d ON fs.churn_date_key = d.date_key
WHERE fs.status = 'Churned'
GROUP BY d.year, d.month_num, d.month_name
ORDER BY d.year, d.month_num;


-- -----------------------------------------------------------------------------
-- Query 9: Cohort Retention by Signup Month
-- Purpose : Cohort heatmap — % of members still active at each tenure milestone
-- -----------------------------------------------------------------------------
SELECT
    signup_cohort.year_month                                AS Signup_Cohort,
    tenure_bands.tenure_band,
    COUNT(fs.subscription_key)                              AS Members_In_Cohort,
    SUM(CASE WHEN fs.status='Active'
            OR fs.tenure_months >= tenure_bands.min_months
            THEN 1 ELSE 0 END)                              AS Retained,
    ROUND(
        SUM(CASE WHEN fs.status='Active'
                OR fs.tenure_months >= tenure_bands.min_months
                THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                       AS Retention_Pct
FROM fact_subscriptions fs
JOIN dim_date signup_cohort ON fs.signup_date_key = signup_cohort.date_key
CROSS JOIN (
    SELECT '0 mo'  AS tenure_band, 0  AS min_months UNION ALL
    SELECT '3 mo'  AS tenure_band, 3  AS min_months UNION ALL
    SELECT '6 mo'  AS tenure_band, 6  AS min_months UNION ALL
    SELECT '12 mo' AS tenure_band, 12 AS min_months UNION ALL
    SELECT '18 mo' AS tenure_band, 18 AS min_months UNION ALL
    SELECT '24 mo' AS tenure_band, 24 AS min_months
) tenure_bands
GROUP BY signup_cohort.year_month, tenure_bands.tenure_band
ORDER BY signup_cohort.year_month, tenure_bands.min_months;


-- -----------------------------------------------------------------------------
-- Query 10: Demographic Breakdown
-- Purpose : Clustered bar — churn by age group and gender
-- -----------------------------------------------------------------------------
SELECT
    m.age_group,
    m.gender,
    COUNT(fs.subscription_key)                              AS Total,
    SUM(CASE WHEN fs.status='Churned' THEN 1 ELSE 0 END)   AS Churned,
    ROUND(
        SUM(CASE WHEN fs.status='Churned' THEN 1 ELSE 0 END)*100.0/COUNT(*),1
    )                                                       AS Churn_Rate_Pct,
    ROUND(AVG(CAST(fs.avg_monthly_visits AS FLOAT)),1)     AS Avg_Visits,
    ROUND(AVG(CAST(fs.nps_score AS FLOAT)),1)              AS Avg_NPS
FROM fact_subscriptions fs
JOIN dim_members m ON fs.member_key = m.member_key
GROUP BY m.age_group, m.gender
ORDER BY m.age_group, m.gender;
