-- =============================================================================
-- DuckDB Schema — Power BI Analytics Portfolio
-- Compatible with DuckDB 0.9+ (no IDENTITY columns; use sequences or rowid)
-- Run via: python database/seed.py  (creates analytics.duckdb automatically)
-- =============================================================================

-- ── Solution 1: Customer Churn ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_date (
    date_key        INTEGER PRIMARY KEY,
    full_date       DATE    NOT NULL,
    year            INTEGER NOT NULL,
    quarter         INTEGER NOT NULL,
    month_num       INTEGER NOT NULL,
    month_name      VARCHAR NOT NULL,
    week_num        INTEGER NOT NULL,
    day_of_week     VARCHAR NOT NULL,
    is_weekend      BOOLEAN NOT NULL,
    fiscal_year     INTEGER NOT NULL,
    fiscal_quarter  INTEGER NOT NULL,
    year_month      VARCHAR NOT NULL   -- 'YYYY-MM' for easy grouping
);

CREATE TABLE IF NOT EXISTS dim_customers (
    customer_key        INTEGER PRIMARY KEY,
    customer_id         VARCHAR NOT NULL UNIQUE,
    full_name           VARCHAR NOT NULL,
    email               VARCHAR NOT NULL,
    country             VARCHAR NOT NULL,
    region              VARCHAR NOT NULL,
    city                VARCHAR NOT NULL,
    signup_date         DATE    NOT NULL,
    age_group           VARCHAR NOT NULL,
    gender              VARCHAR NOT NULL,
    acquisition_channel VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_plans (
    plan_key       INTEGER PRIMARY KEY,
    plan_id        VARCHAR NOT NULL UNIQUE,
    plan_name      VARCHAR NOT NULL,
    billing_cycle  VARCHAR NOT NULL,
    monthly_price  DECIMAL(10,2) NOT NULL,
    tier           VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_segments (
    segment_key   INTEGER PRIMARY KEY,
    segment_id    VARCHAR NOT NULL UNIQUE,
    segment_name  VARCHAR NOT NULL,
    industry      VARCHAR NOT NULL,
    employee_range VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS fact_subscriptions (
    subscription_key INTEGER PRIMARY KEY,
    customer_key     INTEGER NOT NULL REFERENCES dim_customers(customer_key),
    plan_key         INTEGER NOT NULL REFERENCES dim_plans(plan_key),
    segment_key      INTEGER NOT NULL REFERENCES dim_segments(segment_key),
    start_date_key   INTEGER NOT NULL REFERENCES dim_date(date_key),
    end_date_key     INTEGER,
    status           VARCHAR NOT NULL,
    churn_reason     VARCHAR,
    mrr              DECIMAL(12,2) NOT NULL,
    contract_months  INTEGER NOT NULL,
    is_churned       BOOLEAN NOT NULL DEFAULT false,
    is_trial         BOOLEAN NOT NULL DEFAULT false,
    churn_date_key   INTEGER
);

CREATE TABLE IF NOT EXISTS fact_monthly_snapshot (
    snapshot_key        INTEGER PRIMARY KEY,
    customer_key        INTEGER NOT NULL REFERENCES dim_customers(customer_key),
    plan_key            INTEGER NOT NULL REFERENCES dim_plans(plan_key),
    segment_key         INTEGER NOT NULL REFERENCES dim_segments(segment_key),
    snapshot_date_key   INTEGER NOT NULL REFERENCES dim_date(date_key),
    cohort_date_key     INTEGER NOT NULL REFERENCES dim_date(date_key),
    status              VARCHAR NOT NULL,
    mrr                 DECIMAL(12,2) NOT NULL,
    cumulative_spend    DECIMAL(14,2) NOT NULL,
    support_tickets     INTEGER NOT NULL DEFAULT 0,
    logins_last_30d     INTEGER NOT NULL DEFAULT 0,
    feature_usage_score DECIMAL(5,2),
    is_churned          BOOLEAN NOT NULL DEFAULT false,
    months_since_start  INTEGER NOT NULL
);

-- ── Solution 2: Financial P&L + Supply Chain ─────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_accounts (
    account_key     INTEGER PRIMARY KEY,
    account_code    VARCHAR NOT NULL UNIQUE,
    account_name    VARCHAR NOT NULL,
    account_type    VARCHAR NOT NULL,
    pl_category     VARCHAR NOT NULL,
    pl_line         VARCHAR NOT NULL,
    is_debit_normal BOOLEAN NOT NULL,
    display_order   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_cost_centers (
    cost_center_key  INTEGER PRIMARY KEY,
    cost_center_id   VARCHAR NOT NULL UNIQUE,
    cost_center_name VARCHAR NOT NULL,
    department       VARCHAR NOT NULL,
    division         VARCHAR NOT NULL,
    region           VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_products (
    product_key      INTEGER PRIMARY KEY,
    product_id       VARCHAR NOT NULL UNIQUE,
    product_name     VARCHAR NOT NULL,
    category         VARCHAR NOT NULL,
    sub_category     VARCHAR NOT NULL,
    brand            VARCHAR NOT NULL,
    unit_cost        DECIMAL(12,2) NOT NULL,
    unit_price       DECIMAL(12,2) NOT NULL,
    gross_margin_pct DECIMAL(5,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_suppliers (
    supplier_key      INTEGER PRIMARY KEY,
    supplier_id       VARCHAR NOT NULL UNIQUE,
    supplier_name     VARCHAR NOT NULL,
    country           VARCHAR NOT NULL,
    region            VARCHAR NOT NULL,
    lead_time_days    INTEGER NOT NULL,
    reliability_score DECIMAL(5,2),
    category          VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_warehouses (
    warehouse_key  INTEGER PRIMARY KEY,
    warehouse_id   VARCHAR NOT NULL UNIQUE,
    warehouse_name VARCHAR NOT NULL,
    country        VARCHAR NOT NULL,
    region         VARCHAR NOT NULL,
    is_3pl         BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS fact_gl_entries (
    gl_key           INTEGER PRIMARY KEY,
    account_key      INTEGER NOT NULL REFERENCES dim_accounts(account_key),
    cost_center_key  INTEGER NOT NULL REFERENCES dim_cost_centers(cost_center_key),
    product_key      INTEGER REFERENCES dim_products(product_key),
    posting_date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
    fiscal_period    VARCHAR NOT NULL,
    journal_id       VARCHAR NOT NULL,
    description      VARCHAR,
    amount_usd       DECIMAL(18,2) NOT NULL,
    scenario         VARCHAR NOT NULL   -- 'Actual' or 'Budget'
);

CREATE TABLE IF NOT EXISTS fact_sales_orders (
    so_key             INTEGER PRIMARY KEY,
    product_key        INTEGER NOT NULL REFERENCES dim_products(product_key),
    supplier_key       INTEGER REFERENCES dim_suppliers(supplier_key),
    warehouse_key      INTEGER NOT NULL REFERENCES dim_warehouses(warehouse_key),
    cost_center_key    INTEGER NOT NULL REFERENCES dim_cost_centers(cost_center_key),
    order_date_key     INTEGER NOT NULL REFERENCES dim_date(date_key),
    promised_date_key  INTEGER NOT NULL REFERENCES dim_date(date_key),
    delivery_date_key  INTEGER REFERENCES dim_date(date_key),
    so_number          VARCHAR NOT NULL,
    quantity           INTEGER NOT NULL,
    unit_price         DECIMAL(12,2) NOT NULL,
    unit_cost          DECIMAL(12,2) NOT NULL,
    net_revenue        DECIMAL(18,2) NOT NULL,
    cogs               DECIMAL(18,2) NOT NULL,
    gross_profit       DECIMAL(18,2) NOT NULL,
    discount_amount    DECIMAL(18,2) NOT NULL DEFAULT 0,
    is_otif            BOOLEAN,
    is_on_time         BOOLEAN,
    is_in_full         BOOLEAN,
    return_qty         INTEGER NOT NULL DEFAULT 0,
    return_amount      DECIMAL(18,2) NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS fact_inventory_snapshot (
    inv_key           INTEGER PRIMARY KEY,
    product_key       INTEGER NOT NULL REFERENCES dim_products(product_key),
    warehouse_key     INTEGER NOT NULL REFERENCES dim_warehouses(warehouse_key),
    supplier_key      INTEGER REFERENCES dim_suppliers(supplier_key),
    snapshot_date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
    quantity_on_hand  INTEGER NOT NULL,
    quantity_on_order INTEGER NOT NULL DEFAULT 0,
    quantity_available INTEGER NOT NULL,
    unit_cost         DECIMAL(12,2) NOT NULL,
    inventory_value   DECIMAL(18,2) NOT NULL,
    reorder_point     INTEGER NOT NULL,
    is_below_reorder  BOOLEAN NOT NULL DEFAULT false,
    days_of_supply    DECIMAL(8,2),
    stockout_flag     BOOLEAN NOT NULL DEFAULT false
);
