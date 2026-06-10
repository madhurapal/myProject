// =============================================================================
// SOLUTION 1: CUSTOMER CHURN ANALYSIS — POWER QUERY M CODE
// Paste each section into Power BI Advanced Editor (Home > Transform Data > Advanced Editor)
// Author: Madhura Pal | Portfolio Project
// =============================================================================


// =============================================================================
// QUERY 1: dim_Customers — Clean and enrich customer dimension
// =============================================================================
let
    Source = Sql.Database("YOUR_SERVER", "YOUR_DATABASE", [Query="SELECT * FROM dim_customers"]),

    // ── Type enforcement ─────────────────────────────────────────────────────
    TypedTable = Table.TransformColumnTypes(Source, {
        {"customer_key",        Int64.Type},
        {"customer_id",         type text},
        {"first_name",          type text},
        {"last_name",           type text},
        {"email",               type text},
        {"country",             type text},
        {"region",              type text},
        {"city",                type text},
        {"signup_date",         type date},
        {"age_group",           type text},
        {"gender",              type text},
        {"acquisition_channel", type text}
    }),

    // ── Derived columns ──────────────────────────────────────────────────────
    AddFullName = Table.AddColumn(TypedTable, "full_name",
        each [first_name] & " " & [last_name], type text),

    AddTenureMonths = Table.AddColumn(AddFullName, "tenure_months",
        each Date.From(DateTime.LocalNow()) - [signup_date],  // Duration type
        type duration),

    // Convert duration to integer months (for slicers)
    AddTenureMonthsInt = Table.AddColumn(AddTenureMonths, "tenure_months_int",
        each Duration.Days([tenure_months]) // 30,
        Int64.Type),

    // Tenure bucket for segmentation
    AddTenureBucket = Table.AddColumn(AddTenureMonthsInt, "tenure_bucket",
        each if [tenure_months_int] < 3   then "0-3 Months"
             else if [tenure_months_int] < 12  then "3-12 Months"
             else if [tenure_months_int] < 24  then "1-2 Years"
             else if [tenure_months_int] < 48  then "2-4 Years"
             else "4+ Years",
        type text),

    // Email domain (useful for B2B analysis)
    AddEmailDomain = Table.AddColumn(AddTenureBucket, "email_domain",
        each Text.AfterDelimiter([email], "@"), type text),

    // ── Data quality — remove invalid emails ─────────────────────────────────
    FilterValidEmails = Table.SelectRows(AddEmailDomain,
        each Text.Contains([email], "@") and Text.Contains([email], ".")),

    // ── Remove unused columns ────────────────────────────────────────────────
    RemoveCols = Table.RemoveColumns(FilterValidEmails, {"tenure_months"}),

    // ── Sort for readability ─────────────────────────────────────────────────
    SortedTable = Table.Sort(RemoveCols, {{"customer_key", Order.Ascending}})

in
    SortedTable


// =============================================================================
// QUERY 2: fact_MonthlySnapshot — Core table for DAX calculations
// =============================================================================
let
    Source = Sql.Database("YOUR_SERVER", "YOUR_DATABASE", [
        Query="
        SELECT
            fms.*,
            dd_snap.full_date   AS snapshot_date,
            dd_cohort.full_date AS cohort_date,
            dd_snap.year        AS snapshot_year,
            dd_snap.month_num   AS snapshot_month,
            dd_snap.month_name  AS snapshot_month_name,
            dd_snap.fiscal_year,
            dd_snap.fiscal_quarter
        FROM fact_monthly_customer_snapshot fms
        JOIN dim_date dd_snap   ON fms.snapshot_date_key = dd_snap.date_key
        JOIN dim_date dd_cohort ON fms.cohort_date_key   = dd_cohort.date_key
        "
    ]),

    // ── Types ────────────────────────────────────────────────────────────────
    TypedTable = Table.TransformColumnTypes(Source, {
        {"snapshot_key",        Int64.Type},
        {"customer_key",        Int64.Type},
        {"plan_key",            Int64.Type},
        {"segment_key",         Int64.Type},
        {"snapshot_date",       type date},
        {"cohort_date",         type date},
        {"snapshot_year",       Int64.Type},
        {"snapshot_month",      Int64.Type},
        {"snapshot_month_name", type text},
        {"fiscal_year",         Int64.Type},
        {"fiscal_quarter",      Int64.Type},
        {"mrr",                 type number},
        {"cumulative_spend",    type number},
        {"support_tickets",     Int64.Type},
        {"logins_last_30d",     Int64.Type},
        {"feature_usage_score", type number},
        {"is_churned",          type logical},
        {"months_since_start",  Int64.Type},
        {"status",              type text}
    }),

    // ── Derived: Engagement Tier ──────────────────────────────────────────────
    AddEngagementTier = Table.AddColumn(TypedTable, "engagement_tier",
        each if [feature_usage_score] >= 75 then "Power User"
             else if [feature_usage_score] >= 50 then "Active"
             else if [feature_usage_score] >= 25 then "At Risk"
             else "Dormant",
        type text),

    // ── Derived: ARR (Annual Recurring Revenue) ────────────────────────────
    AddARR = Table.AddColumn(AddEngagementTier, "arr",
        each [mrr] * 12, type number),

    // ── Derived: Churn Risk Score (simple rule-based, extensible) ────────────
    AddChurnRiskScore = Table.AddColumn(AddARR, "churn_risk_score",
        each
            let
                usage_score   = if [feature_usage_score] < 20 then 40
                                else if [feature_usage_score] < 40 then 20
                                else 0,
                login_score   = if [logins_last_30d] = 0 then 30
                                else if [logins_last_30d] < 5 then 15
                                else 0,
                ticket_score  = if [support_tickets] > 5 then 30
                                else if [support_tickets] > 2 then 15
                                else 0
            in
                usage_score + login_score + ticket_score,
        Int64.Type),

    // ── Derived: Churn Risk Label ─────────────────────────────────────────────
    AddChurnRiskLabel = Table.AddColumn(AddChurnRiskScore, "churn_risk_label",
        each if [churn_risk_score] >= 70 then "Critical"
             else if [churn_risk_score] >= 40 then "High"
             else if [churn_risk_score] >= 20 then "Medium"
             else "Low",
        type text),

    // ── Cohort Month Label (for x-axis in cohort heatmap) ────────────────────
    AddCohortLabel = Table.AddColumn(AddChurnRiskLabel, "cohort_label",
        each Text.From(Date.Year([cohort_date])) & "-"
             & Text.PadStart(Text.From(Date.Month([cohort_date])), 2, "0"),
        type text),

    // ── Filter out future snapshots (data quality guard) ────────────────────
    FilterFuture = Table.SelectRows(AddCohortLabel,
        each [snapshot_date] <= Date.From(DateTime.LocalNow()))

in
    FilterFuture


// =============================================================================
// QUERY 3: dim_Date — Dedicated date table for time intelligence
// =============================================================================
let
    // Generate full date range
    StartDate  = #date(2020, 1, 1),
    EndDate    = #date(2026, 12, 31),
    DateCount  = Duration.Days(EndDate - StartDate) + 1,
    DateList   = List.Dates(StartDate, DateCount, #duration(1, 0, 0, 0)),
    DateTable  = Table.FromList(DateList, Splitter.SplitByNothing(), {"Date"}),

    // ── Type and basic date parts ─────────────────────────────────────────────
    TypeDate   = Table.TransformColumnTypes(DateTable, {{"Date", type date}}),
    AddYear    = Table.AddColumn(TypeDate,   "Year",         each Date.Year([Date]),         Int64.Type),
    AddQuarter = Table.AddColumn(AddYear,    "Quarter",      each Date.QuarterOfYear([Date]),Int64.Type),
    AddQLabel  = Table.AddColumn(AddQuarter, "Quarter Label",each "Q" & Text.From(Date.QuarterOfYear([Date])), type text),
    AddMonth   = Table.AddColumn(AddQLabel,  "Month Number", each Date.Month([Date]),        Int64.Type),
    AddMonthName = Table.AddColumn(AddMonth, "Month Name",   each Date.MonthName([Date]),    type text),
    AddMonthShort = Table.AddColumn(AddMonthName, "Month Short", each Text.Start(Date.MonthName([Date]), 3), type text),
    AddYearMonth = Table.AddColumn(AddMonthShort, "Year-Month",
        each Text.From(Date.Year([Date])) & "-" & Text.PadStart(Text.From(Date.Month([Date])), 2, "0"),
        type text),

    // Fiscal Year (Apr–Mar)
    AddFiscalYear = Table.AddColumn(AddYearMonth, "Fiscal Year",
        each if Date.Month([Date]) >= 4
             then "FY" & Text.From(Date.Year([Date]) + 1)
             else "FY" & Text.From(Date.Year([Date])),
        type text),
    AddFiscalQ = Table.AddColumn(AddFiscalYear, "Fiscal Quarter",
        each let m = Date.Month([Date])
             in if m >= 4 and m <= 6   then 1
                else if m >= 7 and m <= 9   then 2
                else if m >= 10 and m <= 12 then 3
                else 4,
        Int64.Type),

    // Flags
    AddIsWeekend = Table.AddColumn(AddFiscalQ, "Is Weekend",
        each Date.DayOfWeek([Date], Day.Monday) >= 5, type logical),
    AddIsCurrentMonth = Table.AddColumn(AddIsWeekend, "Is Current Month",
        each Date.Year([Date]) = Date.Year(DateTime.Date(DateTime.LocalNow()))
             and Date.Month([Date]) = Date.Month(DateTime.Date(DateTime.LocalNow())),
        type logical),

    // Date Key (integer YYYYMMDD — matches SQL fact tables)
    AddDateKey = Table.AddColumn(AddIsCurrentMonth, "Date Key",
        each Date.Year([Date]) * 10000 + Date.Month([Date]) * 100 + Date.Day([Date]),
        Int64.Type),

    SortedDate = Table.Sort(AddDateKey, {{"Date", Order.Ascending}})

in
    SortedDate


// =============================================================================
// QUERY 4: Churn_Cohort_Matrix — Pre-aggregated for cohort heatmap visual
// =============================================================================
let
    // Reference the already-loaded fact_MonthlySnapshot query
    Source     = fact_MonthlySnapshot,

    // Keep only columns needed for cohort
    Select     = Table.SelectColumns(Source, {
                    "customer_key", "cohort_label", "months_since_start", "is_churned", "mrr"
                 }),

    // Group by cohort and month offset
    Grouped    = Table.Group(Select,
                    {"cohort_label", "months_since_start"},
                    {
                        {"total_customers",    each Table.RowCount(_),                    Int64.Type},
                        {"churned_customers",  each List.Sum(List.Transform([is_churned],
                                                  each if _ then 1 else 0)),              Int64.Type},
                        {"total_mrr",          each List.Sum([mrr]),                      type number}
                    }),

    // Cohort size (month 0)
    CohortSize = Table.Group(
                    Table.SelectRows(Grouped, each [months_since_start] = 0),
                    {"cohort_label"},
                    {{"cohort_size", each List.Sum([total_customers]), Int64.Type}}
                 ),

    // Join cohort size back
    Joined     = Table.NestedJoin(Grouped, {"cohort_label"}, CohortSize, {"cohort_label"},
                    "cohort_size_tbl", JoinKind.Left),
    Expanded   = Table.ExpandTableColumn(Joined, "cohort_size_tbl", {"cohort_size"}),

    // Retention %
    AddRetention = Table.AddColumn(Expanded, "retention_pct",
                    each if [cohort_size] = null or [cohort_size] = 0 then null
                         else Number.Round([total_customers] / [cohort_size] * 100, 1),
                    type number),

    SortedOut  = Table.Sort(AddRetention, {
                    {"cohort_label",      Order.Ascending},
                    {"months_since_start",Order.Ascending}
                 })
in
    SortedOut
