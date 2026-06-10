// =============================================================================
// SOLUTION 2: FINANCIAL P&L + SUPPLY CHAIN — POWER QUERY M CODE
// Paste each section into Power BI Advanced Editor
// Author: Madhura Pal | Portfolio Project
// =============================================================================


// =============================================================================
// QUERY 1: fact_GL_Entries — Core P&L data with scenario blending
// =============================================================================
let
    // Load Actuals
    Actuals = Sql.Database("YOUR_SERVER", "YOUR_DATABASE", [
        Query="
        SELECT
            fgl.*,
            da.account_name,
            da.account_type,
            da.pl_category,
            da.pl_line,
            da.is_debit_normal,
            da.display_order,
            dcc.department,
            dcc.division,
            dcc.region         AS cost_center_region,
            dd.full_date       AS posting_date,
            dd.year,
            dd.month_num,
            dd.month_name,
            dd.fiscal_year,
            dd.fiscal_quarter
        FROM fact_gl_entries fgl
        JOIN dim_accounts     da  ON fgl.account_key     = da.account_key
        JOIN dim_cost_centers dcc ON fgl.cost_center_key = dcc.cost_center_key
        JOIN dim_date         dd  ON fgl.posting_date_key= dd.date_key
        WHERE fgl.scenario = 'Actual'
        "
    ]),

    // Load Budget
    Budget = Sql.Database("YOUR_SERVER", "YOUR_DATABASE", [
        Query="
        SELECT
            fb.*,
            da.account_name,
            da.account_type,
            da.pl_category,
            da.pl_line,
            da.is_debit_normal,
            da.display_order,
            dcc.department,
            dcc.division,
            dcc.region         AS cost_center_region,
            dd.full_date       AS budget_date,
            dd.year,
            dd.month_num,
            dd.month_name,
            dd.fiscal_year,
            dd.fiscal_quarter,
            'Budget'           AS scenario,
            fb.budget_amount_usd AS amount_usd
        FROM fact_budget fb
        JOIN dim_accounts     da  ON fb.account_key     = da.account_key
        JOIN dim_cost_centers dcc ON fb.cost_center_key = dcc.cost_center_key
        JOIN dim_date         dd  ON fb.budget_date_key = dd.date_key
        WHERE fb.budget_type = 'Annual Budget'
        "
    ]),

    // Standardise columns before append
    ActualsSelect = Table.SelectColumns(Actuals, {
        "account_key","account_name","account_type","pl_category","pl_line",
        "is_debit_normal","display_order","department","division","cost_center_region",
        "posting_date","year","month_num","month_name","fiscal_year","fiscal_quarter",
        "amount_usd","scenario","fiscal_period","currency"
    }),
    BudgetSelect = Table.RenameColumns(
        Table.SelectColumns(Budget, {
            "account_key","account_name","account_type","pl_category","pl_line",
            "is_debit_normal","display_order","department","division","cost_center_region",
            "budget_date","year","month_num","month_name","fiscal_year","fiscal_quarter",
            "amount_usd","scenario","fiscal_period"
        }),
        {{"budget_date","posting_date"}}
    ),
    BudgetWithCurrency = Table.AddColumn(BudgetSelect, "currency", each "USD", type text),

    // Combine Actual + Budget into one unified table
    Combined = Table.Combine({ActualsSelect, BudgetWithCurrency}),

    // ── P&L Sign Convention ──────────────────────────────────────────────────
    // Revenue lines need to flip sign so they show as positive in P&L reports
    AddSignedAmount = Table.AddColumn(Combined, "signed_amount",
        each if [is_debit_normal] = 0 then [amount_usd]    // Revenue → positive
             else -[amount_usd],                            // Cost   → negative
        type number),

    // ── Variance flag (for conditional formatting in Power BI) ───────────────
    AddPLSign = Table.AddColumn(AddSignedAmount, "pl_sign",
        each if [account_type] = "Revenue" then 1 else -1,
        Int64.Type),

    TypedFinal = Table.TransformColumnTypes(Combined, {
        {"year",           Int64.Type},
        {"month_num",      Int64.Type},
        {"fiscal_year",    Int64.Type},
        {"fiscal_quarter", Int64.Type},
        {"amount_usd",     type number},
        {"posting_date",   type date}
    })

in
    TypedFinal


// =============================================================================
// QUERY 2: fact_SalesOrders — Enriched for supply chain KPIs
// =============================================================================
let
    Source = Sql.Database("YOUR_SERVER", "YOUR_DATABASE", [
        Query="
        SELECT
            fso.*,
            dp.product_name,
            dp.category         AS product_category,
            dp.sub_category,
            dp.brand,
            ds.supplier_name,
            ds.country          AS supplier_country,
            ds.lead_time_days,
            ds.reliability_score,
            dw.warehouse_name,
            dw.region           AS warehouse_region,
            dw.country          AS warehouse_country,
            dcc.division,
            dcc.department,
            dd_order.full_date  AS order_date,
            dd_order.year       AS order_year,
            dd_order.month_num  AS order_month,
            dd_order.fiscal_year,
            dd_order.fiscal_quarter,
            dd_ship.full_date   AS ship_date,
            dd_del.full_date    AS delivery_date,
            dd_prom.full_date   AS promised_date
        FROM fact_sales_orders fso
        JOIN dim_products     dp  ON fso.product_key      = dp.product_key
        LEFT JOIN dim_suppliers ds ON fso.supplier_key    = ds.supplier_key
        JOIN dim_warehouses   dw  ON fso.warehouse_key    = dw.warehouse_key
        JOIN dim_cost_centers dcc ON fso.cost_center_key  = dcc.cost_center_key
        JOIN dim_date  dd_order   ON fso.order_date_key   = dd_order.date_key
        LEFT JOIN dim_date dd_ship ON fso.ship_date_key   = dd_ship.date_key
        LEFT JOIN dim_date dd_del  ON fso.delivery_date_key= dd_del.date_key
        JOIN dim_date  dd_prom    ON fso.promised_date_key = dd_prom.date_key
        "
    ]),

    // ── Types ────────────────────────────────────────────────────────────────
    Typed = Table.TransformColumnTypes(Source, {
        {"order_date",       type date},
        {"ship_date",        type date},
        {"delivery_date",    type date},
        {"promised_date",    type date},
        {"gross_revenue",    type number},
        {"net_revenue",      type number},
        {"cogs",             type number},
        {"gross_profit",     type number},
        {"discount_amount",  type number},
        {"return_amount",    type number},
        {"is_otif",          type logical},
        {"is_on_time",       type logical},
        {"is_in_full",       type logical},
        {"quantity",         Int64.Type},
        {"return_qty",       Int64.Type},
        {"order_year",       Int64.Type},
        {"order_month",      Int64.Type},
        {"fiscal_year",      Int64.Type},
        {"fiscal_quarter",   Int64.Type}
    }),

    // ── Gross Margin % ───────────────────────────────────────────────────────
    AddGM = Table.AddColumn(Typed, "gross_margin_pct",
        each if [net_revenue] = 0 then null
             else Number.Round([gross_profit] / [net_revenue] * 100, 2),
        type number),

    // ── Days to Ship ─────────────────────────────────────────────────────────
    AddDaysToShip = Table.AddColumn(AddGM, "days_to_ship",
        each if [ship_date] = null then null
             else Duration.Days([ship_date] - [order_date]),
        Int64.Type),

    // ── Days Late (delivery vs promise) ──────────────────────────────────────
    AddDaysLate = Table.AddColumn(AddDaysToShip, "days_late",
        each if [delivery_date] = null then null
             else Duration.Days([delivery_date] - [promised_date]),
        Int64.Type),

    // ── OTIF label ───────────────────────────────────────────────────────────
    AddOTIFLabel = Table.AddColumn(AddDaysLate, "otif_label",
        each if [is_otif] = true then "OTIF"
             else if [is_on_time] = true and [is_in_full] <> true then "On Time, Short"
             else if [is_on_time] <> true and [is_in_full] = true then "In Full, Late"
             else "Failed",
        type text),

    // ── Discount % ───────────────────────────────────────────────────────────
    AddDiscountPct = Table.AddColumn(AddOTIFLabel, "discount_pct",
        each if [gross_revenue] = 0 then null
             else Number.Round([discount_amount] / [gross_revenue] * 100, 2),
        type number)

in
    AddDiscountPct


// =============================================================================
// QUERY 3: fact_Inventory — Enriched inventory snapshot
// =============================================================================
let
    Source = Sql.Database("YOUR_SERVER", "YOUR_DATABASE", [
        Query="
        SELECT
            fis.*,
            dp.product_name,
            dp.category,
            dp.sub_category,
            dp.brand,
            dp.unit_price,
            ds.supplier_name,
            ds.lead_time_days,
            dw.warehouse_name,
            dw.region,
            dw.is_3pl,
            dd.full_date     AS snapshot_date,
            dd.year,
            dd.month_num,
            dd.month_name,
            dd.fiscal_year
        FROM fact_inventory_snapshot fis
        JOIN dim_products   dp ON fis.product_key   = dp.product_key
        LEFT JOIN dim_suppliers ds ON fis.supplier_key = ds.supplier_key
        JOIN dim_warehouses dw ON fis.warehouse_key  = dw.warehouse_key
        JOIN dim_date       dd ON fis.snapshot_date_key = dd.date_key
        "
    ]),

    Typed = Table.TransformColumnTypes(Source, {
        {"snapshot_date",    type date},
        {"inventory_value",  type number},
        {"unit_cost",        type number},
        {"quantity_on_hand", Int64.Type},
        {"quantity_on_order",Int64.Type},
        {"quantity_available",Int64.Type},
        {"days_of_supply",   type number},
        {"is_below_reorder", type logical},
        {"stockout_flag",    type logical},
        {"year",             Int64.Type},
        {"month_num",        Int64.Type},
        {"fiscal_year",      Int64.Type}
    }),

    // ── Potential Revenue at Risk from stockouts ──────────────────────────────
    AddRevenueAtRisk = Table.AddColumn(Typed, "revenue_at_risk",
        each if [stockout_flag] = true
             then [unit_price] * [reorder_point]   // Conservative: reorder_point * price
             else 0,
        type number),

    // ── Inventory Coverage Label ──────────────────────────────────────────────
    AddCoverageLabel = Table.AddColumn(AddRevenueAtRisk, "stock_health",
        each if [stockout_flag] = true then "Stockout"
             else if [is_below_reorder] = true then "Critical — Below Reorder"
             else if [days_of_supply] < 7  then "Low Stock"
             else if [days_of_supply] < 30 then "Healthy"
             else "Overstocked",
        type text)

in
    AddCoverageLabel


// =============================================================================
// QUERY 4: P&L_Variance_Bridge — Pre-aggregated actual vs budget
//          Powers the waterfall / bridge chart directly
// =============================================================================
let
    Source = fact_GL_Entries,  // References Query 1 above

    // Split Actual and Budget
    Actual = Table.SelectRows(Source, each [scenario] = "Actual"),
    Budget = Table.SelectRows(Source, each [scenario] = "Budget"),

    // Aggregate Actual by P&L line and period
    ActGroup = Table.Group(Actual,
        {"fiscal_year","fiscal_quarter","pl_category","pl_line","display_order","account_type"},
        {{"actual_amount", each List.Sum([signed_amount]), type number}}
    ),

    // Aggregate Budget
    BudGroup = Table.Group(Budget,
        {"fiscal_year","fiscal_quarter","pl_category","pl_line","display_order","account_type"},
        {{"budget_amount", each List.Sum([signed_amount]), type number}}
    ),

    // Merge
    Merged = Table.NestedJoin(ActGroup, {"fiscal_year","fiscal_quarter","pl_line"},
                              BudGroup, {"fiscal_year","fiscal_quarter","pl_line"},
                              "BudgetData", JoinKind.FullOuter),
    Expanded = Table.ExpandTableColumn(Merged, "BudgetData", {"budget_amount"}),

    // Variance
    AddVariance = Table.AddColumn(Expanded, "variance_abs",
        each (if [actual_amount] = null then 0 else [actual_amount])
           - (if [budget_amount] = null then 0 else [budget_amount]),
        type number),

    AddVariancePct = Table.AddColumn(AddVariance, "variance_pct",
        each if [budget_amount] = null or [budget_amount] = 0 then null
             else Number.Round([variance_abs] / Number.Abs([budget_amount]) * 100, 2),
        type number),

    // Favorable/Unfavorable flag (Revenue: positive = favorable; Cost: negative = favorable)
    AddFlag = Table.AddColumn(AddVariancePct, "variance_flag",
        each if [account_type] = "Revenue" and [variance_abs] >= 0 then "Favorable"
             else if [account_type] <> "Revenue" and [variance_abs] >= 0 then "Favorable"
             else "Unfavorable",
        type text),

    SortedOut = Table.Sort(AddFlag, {
        {"fiscal_year",    Order.Ascending},
        {"fiscal_quarter", Order.Ascending},
        {"display_order",  Order.Ascending}
    })

in
    SortedOut
