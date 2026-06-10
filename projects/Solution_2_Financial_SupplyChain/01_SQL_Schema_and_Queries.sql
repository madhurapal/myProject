-- =============================================================================
-- SOLUTION 2: FINANCIAL P&L VARIANCE + SUPPLY CHAIN KPI TRACKING
-- Star Schema DDL + Data Generation + Analytical Queries
-- Scales to 2M+ rows | SQL Server / PostgreSQL compatible
-- Author: Madhura Pal | Portfolio Project
-- =============================================================================


-- =============================================================================
-- SECTION 1: DIMENSION TABLES (DDL)
-- =============================================================================

-- Chart of Accounts Dimension
CREATE TABLE dim_accounts (
    account_key         INT           PRIMARY KEY IDENTITY(1,1),
    account_code        VARCHAR(20)   NOT NULL UNIQUE,
    account_name        VARCHAR(200)  NOT NULL,
    account_type        VARCHAR(50)   NOT NULL,   -- 'Revenue','COGS','OpEx','Other'
    pl_category         VARCHAR(100)  NOT NULL,   -- 'Net Revenue','Gross Profit','EBITDA','Net Income'
    pl_line             VARCHAR(200)  NOT NULL,   -- Specific P&L line item
    is_debit_normal     BIT           NOT NULL,   -- 1=Expense/Asset, 0=Revenue/Liability
    parent_account_code VARCHAR(20),
    display_order       INT           NOT NULL
);

-- Cost Center Dimension
CREATE TABLE dim_cost_centers (
    cost_center_key     INT           PRIMARY KEY IDENTITY(1,1),
    cost_center_id      VARCHAR(20)   NOT NULL UNIQUE,
    cost_center_name    VARCHAR(200)  NOT NULL,
    department          VARCHAR(100)  NOT NULL,   -- 'Sales','Marketing','Engineering','G&A'
    division            VARCHAR(100)  NOT NULL,
    region              VARCHAR(100)  NOT NULL,
    manager_name        VARCHAR(200)
);

-- Product Dimension
CREATE TABLE dim_products (
    product_key         INT           PRIMARY KEY IDENTITY(1,1),
    product_id          VARCHAR(20)   NOT NULL UNIQUE,
    product_name        VARCHAR(200)  NOT NULL,
    category            VARCHAR(100)  NOT NULL,
    sub_category        VARCHAR(100),
    brand               VARCHAR(100),
    unit_cost           DECIMAL(12,2) NOT NULL,
    unit_price          DECIMAL(12,2) NOT NULL,
    gross_margin_pct    DECIMAL(5,2)  NOT NULL,
    sku                 VARCHAR(50)   NOT NULL,
    is_active           BIT           NOT NULL DEFAULT 1
);

-- Supplier Dimension
CREATE TABLE dim_suppliers (
    supplier_key        INT           PRIMARY KEY IDENTITY(1,1),
    supplier_id         VARCHAR(20)   NOT NULL UNIQUE,
    supplier_name       VARCHAR(200)  NOT NULL,
    country             VARCHAR(100)  NOT NULL,
    region              VARCHAR(100)  NOT NULL,
    lead_time_days      INT           NOT NULL,
    reliability_score   DECIMAL(5,2),   -- 0-100
    payment_terms_days  INT           NOT NULL,
    category            VARCHAR(100)  NOT NULL
);

-- Warehouse / Location Dimension
CREATE TABLE dim_warehouses (
    warehouse_key       INT           PRIMARY KEY IDENTITY(1,1),
    warehouse_id        VARCHAR(20)   NOT NULL UNIQUE,
    warehouse_name      VARCHAR(200)  NOT NULL,
    country             VARCHAR(100)  NOT NULL,
    region              VARCHAR(100)  NOT NULL,
    capacity_units      INT           NOT NULL,
    is_3pl              BIT           NOT NULL DEFAULT 0   -- Third-party logistics?
);


-- =============================================================================
-- SECTION 2: FACT TABLES (DDL)
-- =============================================================================

-- GL Journal Entries Fact (core P&L table)
CREATE TABLE fact_gl_entries (
    gl_key              BIGINT        PRIMARY KEY IDENTITY(1,1),
    account_key         INT           NOT NULL REFERENCES dim_accounts(account_key),
    cost_center_key     INT           NOT NULL REFERENCES dim_cost_centers(cost_center_key),
    product_key         INT           REFERENCES dim_products(product_key),
    posting_date_key    INT           NOT NULL REFERENCES dim_date(date_key),
    fiscal_period       VARCHAR(10)   NOT NULL,  -- e.g., 'FY2026-Q1'
    journal_id          VARCHAR(50)   NOT NULL,
    description         VARCHAR(500),
    amount              DECIMAL(18,2) NOT NULL,  -- Positive = credit; direction from is_debit_normal
    currency            VARCHAR(5)    NOT NULL DEFAULT 'USD',
    fx_rate             DECIMAL(12,6) NOT NULL DEFAULT 1.0,
    amount_usd          DECIMAL(18,2) NOT NULL,
    scenario            VARCHAR(20)   NOT NULL   -- 'Actual','Budget','Forecast'
);

-- Budget Fact (plan/budget entries by account, period, cost center)
CREATE TABLE fact_budget (
    budget_key          BIGINT        PRIMARY KEY IDENTITY(1,1),
    account_key         INT           NOT NULL REFERENCES dim_accounts(account_key),
    cost_center_key     INT           NOT NULL REFERENCES dim_cost_centers(cost_center_key),
    product_key         INT           REFERENCES dim_products(product_key),
    budget_date_key     INT           NOT NULL REFERENCES dim_date(date_key),
    fiscal_period       VARCHAR(10)   NOT NULL,
    budget_type         VARCHAR(20)   NOT NULL,  -- 'Annual Budget','Revised Forecast'
    budget_amount_usd   DECIMAL(18,2) NOT NULL,
    version             INT           NOT NULL DEFAULT 1
);

-- Purchase Orders Fact
CREATE TABLE fact_purchase_orders (
    po_key              BIGINT        PRIMARY KEY IDENTITY(1,1),
    supplier_key        INT           NOT NULL REFERENCES dim_suppliers(supplier_key),
    product_key         INT           NOT NULL REFERENCES dim_products(product_key),
    warehouse_key       INT           NOT NULL REFERENCES dim_warehouses(warehouse_key),
    order_date_key      INT           NOT NULL REFERENCES dim_date(date_key),
    expected_date_key   INT           NOT NULL REFERENCES dim_date(date_key),
    actual_receipt_key  INT           REFERENCES dim_date(date_key),
    po_number           VARCHAR(50)   NOT NULL,
    quantity_ordered    INT           NOT NULL,
    quantity_received   INT,
    unit_cost           DECIMAL(12,2) NOT NULL,
    total_cost          DECIMAL(18,2) NOT NULL,
    status              VARCHAR(30)   NOT NULL,  -- 'Open','Received','Partial','Cancelled'
    is_on_time          BIT,                     -- NULL = not yet received
    days_late           INT,                     -- Negative = early
    quality_reject_qty  INT           NOT NULL DEFAULT 0
);

-- Sales Orders Fact
CREATE TABLE fact_sales_orders (
    so_key              BIGINT        PRIMARY KEY IDENTITY(1,1),
    product_key         INT           NOT NULL REFERENCES dim_products(product_key),
    supplier_key        INT           REFERENCES dim_suppliers(supplier_key),
    warehouse_key       INT           NOT NULL REFERENCES dim_warehouses(warehouse_key),
    cost_center_key     INT           NOT NULL REFERENCES dim_cost_centers(cost_center_key),
    order_date_key      INT           NOT NULL REFERENCES dim_date(date_key),
    ship_date_key       INT           REFERENCES dim_date(date_key),
    delivery_date_key   INT           REFERENCES dim_date(date_key),
    promised_date_key   INT           NOT NULL REFERENCES dim_date(date_key),
    so_number           VARCHAR(50)   NOT NULL,
    quantity            INT           NOT NULL,
    unit_price          DECIMAL(12,2) NOT NULL,
    unit_cost           DECIMAL(12,2) NOT NULL,
    gross_revenue       DECIMAL(18,2) NOT NULL,
    discount_amount     DECIMAL(18,2) NOT NULL DEFAULT 0,
    net_revenue         DECIMAL(18,2) NOT NULL,
    cogs                DECIMAL(18,2) NOT NULL,
    gross_profit        DECIMAL(18,2) NOT NULL,
    is_otif             BIT,          -- On Time In Full
    is_on_time          BIT,
    is_in_full          BIT,
    return_qty          INT           NOT NULL DEFAULT 0,
    return_amount       DECIMAL(18,2) NOT NULL DEFAULT 0
);

-- Inventory Snapshot Fact (daily/weekly snapshot for stock analysis)
CREATE TABLE fact_inventory_snapshot (
    inv_key             BIGINT        PRIMARY KEY IDENTITY(1,1),
    product_key         INT           NOT NULL REFERENCES dim_products(product_key),
    warehouse_key       INT           NOT NULL REFERENCES dim_warehouses(warehouse_key),
    supplier_key        INT           REFERENCES dim_suppliers(supplier_key),
    snapshot_date_key   INT           NOT NULL REFERENCES dim_date(date_key),
    quantity_on_hand    INT           NOT NULL,
    quantity_on_order   INT           NOT NULL DEFAULT 0,
    quantity_reserved   INT           NOT NULL DEFAULT 0,
    quantity_available  INT           NOT NULL,
    unit_cost           DECIMAL(12,2) NOT NULL,
    inventory_value     DECIMAL(18,2) NOT NULL,
    reorder_point       INT           NOT NULL,
    is_below_reorder    BIT           NOT NULL DEFAULT 0,
    days_of_supply      DECIMAL(8,2),
    stockout_flag       BIT           NOT NULL DEFAULT 0
);


-- =============================================================================
-- SECTION 3: CHART OF ACCOUNTS SEED DATA
-- =============================================================================

INSERT INTO dim_accounts (account_code, account_name, account_type, pl_category, pl_line,
                           is_debit_normal, display_order) VALUES
-- Revenue
('4000', 'Product Revenue',         'Revenue', 'Net Revenue',   'Product Revenue',      0, 10),
('4010', 'Service Revenue',         'Revenue', 'Net Revenue',   'Service Revenue',      0, 20),
('4020', 'Subscription Revenue',    'Revenue', 'Net Revenue',   'Subscription Revenue', 0, 30),
('4090', 'Returns & Discounts',     'Revenue', 'Net Revenue',   'Less: Returns',        1, 40),
-- COGS
('5000', 'Direct Material Cost',    'COGS',    'Gross Profit',  'COGS - Materials',     1, 60),
('5010', 'Direct Labor Cost',       'COGS',    'Gross Profit',  'COGS - Labor',         1, 70),
('5020', 'Freight & Logistics',     'COGS',    'Gross Profit',  'COGS - Freight',       1, 80),
('5030', 'Manufacturing Overhead',  'COGS',    'Gross Profit',  'COGS - Overhead',      1, 90),
-- Operating Expenses
('6000', 'Sales Compensation',      'OpEx',    'EBITDA',        'Sales & Marketing',    1, 120),
('6010', 'Marketing Spend',         'OpEx',    'EBITDA',        'Sales & Marketing',    1, 130),
('6020', 'R&D Expenses',            'OpEx',    'EBITDA',        'R&D',                  1, 140),
('6030', 'G&A Expenses',            'OpEx',    'EBITDA',        'G&A',                  1, 150),
('6040', 'IT & Infrastructure',     'OpEx',    'EBITDA',        'G&A',                  1, 160),
-- Below EBITDA
('7000', 'Depreciation',            'OpEx',    'Net Income',    'D&A',                  1, 180),
('7010', 'Amortization',            'OpEx',    'Net Income',    'D&A',                  1, 190),
('7020', 'Interest Expense',        'Other',   'Net Income',    'Interest',             1, 200),
('8000', 'Income Tax Expense',      'Other',   'Net Income',    'Tax',                  1, 210);


-- =============================================================================
-- SECTION 4: ANALYTICAL QUERIES
-- =============================================================================

-- -----------------------------------------------------------------------
-- Q1: P&L Summary — Actual vs Budget Variance by Fiscal Period
-- -----------------------------------------------------------------------
WITH actual AS (
    SELECT
        account_key,
        fiscal_period,
        SUM(amount_usd) AS actual_amount
    FROM fact_gl_entries
    WHERE scenario = 'Actual'
    GROUP BY account_key, fiscal_period
),
budget AS (
    SELECT
        account_key,
        fiscal_period,
        SUM(budget_amount_usd) AS budget_amount
    FROM fact_budget
    WHERE budget_type = 'Annual Budget'
    GROUP BY account_key, fiscal_period
)
SELECT
    da.pl_category,
    da.pl_line,
    da.account_name,
    da.display_order,
    a.fiscal_period,
    ISNULL(a.actual_amount, 0)                                  AS actual,
    ISNULL(b.budget_amount, 0)                                  AS budget,
    ISNULL(a.actual_amount, 0) - ISNULL(b.budget_amount, 0)    AS variance_abs,
    ROUND(
        (ISNULL(a.actual_amount,0) - ISNULL(b.budget_amount,0))
        / NULLIF(ABS(b.budget_amount), 0) * 100, 2
    )                                                           AS variance_pct,
    CASE
        WHEN da.account_type = 'Revenue'
             AND (ISNULL(a.actual_amount,0) - ISNULL(b.budget_amount,0)) >= 0 THEN 'Favorable'
        WHEN da.account_type IN ('COGS','OpEx')
             AND (ISNULL(a.actual_amount,0) - ISNULL(b.budget_amount,0)) <= 0 THEN 'Favorable'
        ELSE 'Unfavorable'
    END                                                         AS variance_flag
FROM dim_accounts da
LEFT JOIN actual a ON da.account_key = a.account_key
LEFT JOIN budget b ON da.account_key = b.account_key AND a.fiscal_period = b.fiscal_period
ORDER BY da.display_order, a.fiscal_period;


-- -----------------------------------------------------------------------
-- Q2: Waterfall P&L — Cascading Subtotals for a Single Period
-- -----------------------------------------------------------------------
WITH period_actuals AS (
    SELECT
        da.pl_category,
        da.pl_line,
        da.account_type,
        da.is_debit_normal,
        da.display_order,
        SUM(fgl.amount_usd) AS raw_amount
    FROM fact_gl_entries fgl
    JOIN dim_accounts da ON fgl.account_key = da.account_key
    WHERE fgl.scenario    = 'Actual'
      AND fgl.fiscal_period = 'FY2026-Q1'   -- Parameterize in Power BI
    GROUP BY da.pl_category, da.pl_line, da.account_type, da.is_debit_normal, da.display_order
),
signed AS (
    SELECT
        pl_category, pl_line, account_type, display_order,
        -- Flip sign: Revenue shown positive, Costs shown negative in P&L
        CASE WHEN is_debit_normal = 0 THEN raw_amount ELSE -raw_amount END AS pl_amount
    FROM period_actuals
)
SELECT
    pl_category,
    pl_line,
    account_type,
    display_order,
    SUM(pl_amount)                               AS line_amount,
    SUM(SUM(pl_amount)) OVER (
        ORDER BY display_order
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                            AS running_total_net_income
FROM signed
GROUP BY pl_category, pl_line, account_type, display_order
ORDER BY display_order;


-- -----------------------------------------------------------------------
-- Q3: Revenue Bridge — Current Period vs Prior Period (YoY / QoQ)
-- -----------------------------------------------------------------------
WITH current_period AS (
    SELECT
        da.pl_line,
        dcc.division,
        dp.category    AS product_category,
        SUM(fgl.amount_usd) AS current_revenue
    FROM fact_gl_entries fgl
    JOIN dim_accounts     da  ON fgl.account_key      = da.account_key
    JOIN dim_cost_centers dcc ON fgl.cost_center_key  = dcc.cost_center_key
    JOIN dim_products     dp  ON fgl.product_key      = dp.product_key
    WHERE fgl.scenario    = 'Actual'
      AND fgl.fiscal_period = 'FY2026-Q1'
      AND da.account_type   = 'Revenue'
    GROUP BY da.pl_line, dcc.division, dp.category
),
prior_period AS (
    SELECT
        da.pl_line,
        dcc.division,
        dp.category    AS product_category,
        SUM(fgl.amount_usd) AS prior_revenue
    FROM fact_gl_entries fgl
    JOIN dim_accounts     da  ON fgl.account_key      = da.account_key
    JOIN dim_cost_centers dcc ON fgl.cost_center_key  = dcc.cost_center_key
    JOIN dim_products     dp  ON fgl.product_key      = dp.product_key
    WHERE fgl.scenario    = 'Actual'
      AND fgl.fiscal_period = 'FY2025-Q1'   -- Same quarter prior year
      AND da.account_type   = 'Revenue'
    GROUP BY da.pl_line, dcc.division, dp.category
)
SELECT
    c.pl_line,
    c.division,
    c.product_category,
    ISNULL(c.current_revenue, 0)                                    AS current_revenue,
    ISNULL(p.prior_revenue, 0)                                      AS prior_revenue,
    ISNULL(c.current_revenue,0) - ISNULL(p.prior_revenue,0)        AS variance_yoy,
    ROUND(
        (ISNULL(c.current_revenue,0) - ISNULL(p.prior_revenue,0))
        / NULLIF(p.prior_revenue, 0) * 100, 2
    )                                                               AS yoy_growth_pct
FROM current_period c
FULL OUTER JOIN prior_period p
    ON c.pl_line = p.pl_line AND c.division = p.division AND c.product_category = p.product_category
ORDER BY variance_yoy DESC;


-- -----------------------------------------------------------------------
-- Q4: Supply Chain OTIF (On Time In Full) by Supplier, Product, Region
-- -----------------------------------------------------------------------
SELECT
    ds.supplier_name,
    ds.country                          AS supplier_country,
    ds.reliability_score,
    dp.category                         AS product_category,
    dw.region                           AS warehouse_region,
    COUNT(*)                            AS total_orders,
    SUM(CASE WHEN fso.is_otif  = 1 THEN 1 ELSE 0 END)     AS otif_count,
    SUM(CASE WHEN fso.is_on_time = 1 THEN 1 ELSE 0 END)   AS on_time_count,
    SUM(CASE WHEN fso.is_in_full = 1 THEN 1 ELSE 0 END)   AS in_full_count,
    ROUND(CAST(SUM(CASE WHEN fso.is_otif = 1 THEN 1 ELSE 0 END) AS FLOAT)
          / NULLIF(COUNT(*),0) * 100, 2)                   AS otif_rate_pct,
    SUM(fso.return_qty)                 AS total_returns,
    SUM(fso.return_amount)              AS return_value,
    SUM(fso.gross_revenue)              AS total_revenue
FROM fact_sales_orders fso
JOIN dim_suppliers  ds ON fso.supplier_key  = ds.supplier_key
JOIN dim_products   dp ON fso.product_key   = dp.product_key
JOIN dim_warehouses dw ON fso.warehouse_key = dw.warehouse_key
GROUP BY ds.supplier_name, ds.country, ds.reliability_score, dp.category, dw.region
ORDER BY otif_rate_pct ASC;


-- -----------------------------------------------------------------------
-- Q5: Inventory Turnover and Days on Hand by Product Category
-- -----------------------------------------------------------------------
WITH cogs_by_product AS (
    SELECT
        product_key,
        SUM(cogs) AS total_cogs
    FROM fact_sales_orders
    WHERE order_date_key BETWEEN 20250101 AND 20251231   -- Full year
    GROUP BY product_key
),
avg_inventory AS (
    SELECT
        product_key,
        warehouse_key,
        AVG(CAST(quantity_on_hand AS FLOAT)) AS avg_qty_on_hand,
        AVG(inventory_value)                 AS avg_inventory_value
    FROM fact_inventory_snapshot
    WHERE snapshot_date_key BETWEEN 20250101 AND 20251231
    GROUP BY product_key, warehouse_key
)
SELECT
    dp.category,
    dp.sub_category,
    dw.region,
    SUM(ai.avg_inventory_value)                                    AS avg_inventory_value,
    SUM(cb.total_cogs)                                             AS annual_cogs,
    ROUND(SUM(cb.total_cogs) / NULLIF(SUM(ai.avg_inventory_value),0), 2)
                                                                   AS inventory_turnover,
    ROUND(365.0 / NULLIF(SUM(cb.total_cogs) / NULLIF(SUM(ai.avg_inventory_value),0), 0), 1)
                                                                   AS days_on_hand,
    SUM(CASE WHEN fis.stockout_flag = 1 THEN 1 ELSE 0 END)        AS stockout_occurrences
FROM avg_inventory ai
JOIN dim_products          dp  ON ai.product_key   = dp.product_key
JOIN dim_warehouses        dw  ON ai.warehouse_key = dw.warehouse_key
LEFT JOIN cogs_by_product  cb  ON ai.product_key   = cb.product_key
LEFT JOIN fact_inventory_snapshot fis
    ON ai.product_key = fis.product_key AND ai.warehouse_key = fis.warehouse_key
GROUP BY dp.category, dp.sub_category, dw.region
ORDER BY inventory_turnover ASC;  -- Lowest turnover = overstocked / slow-moving


-- -----------------------------------------------------------------------
-- Q6: Supplier Lead Time Performance (PO actual vs promised)
-- -----------------------------------------------------------------------
SELECT
    ds.supplier_name,
    ds.country,
    dp.category,
    COUNT(fpo.po_key)                                              AS total_pos,
    AVG(CAST(fpo.days_late AS FLOAT))                             AS avg_days_late,
    AVG(CAST(ds.lead_time_days AS FLOAT))                         AS contracted_lead_days,
    AVG(
        DATEDIFF(DAY,
            (SELECT full_date FROM dim_date WHERE date_key = fpo.order_date_key),
            (SELECT full_date FROM dim_date WHERE date_key = fpo.actual_receipt_key)
        )
    )                                                             AS actual_avg_lead_days,
    SUM(CASE WHEN fpo.is_on_time = 0 THEN 1 ELSE 0 END)          AS late_deliveries,
    ROUND(CAST(SUM(CASE WHEN fpo.is_on_time = 1 THEN 1 ELSE 0 END) AS FLOAT)
          / NULLIF(COUNT(*), 0) * 100, 2)                         AS on_time_delivery_pct,
    SUM(fpo.quality_reject_qty)                                   AS total_rejects,
    ROUND(CAST(SUM(fpo.quality_reject_qty) AS FLOAT)
          / NULLIF(SUM(fpo.quantity_received), 0) * 100, 2)       AS defect_rate_pct
FROM fact_purchase_orders fpo
JOIN dim_suppliers ds ON fpo.supplier_key = ds.supplier_key
JOIN dim_products  dp ON fpo.product_key  = dp.product_key
WHERE fpo.status IN ('Received','Partial')
GROUP BY ds.supplier_name, ds.country, dp.category
ORDER BY on_time_delivery_pct ASC;
