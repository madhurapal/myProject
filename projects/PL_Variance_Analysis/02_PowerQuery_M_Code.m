// =============================================================================
// NovaStar Financial Group — P&L Variance Analysis
// Power Query M Transformations
// Load 2.6M+ actual rows + budget + dimension tables → star schema in Power BI
// =============================================================================


// ── TABLE 1: fact_Actual (combine 3 CSV files) ────────────────────────────────
let
    // Point this to the folder containing actual_2022.csv, actual_2023.csv, actual_2024.csv
    Source = Folder.Files("C:\NovaStar\data"),

    // Keep only the three actual CSV files
    ActualFiles = Table.SelectRows(Source, each Text.StartsWith([Name], "actual_")),

    // Load and combine all CSVs
    LoadCSV = Table.AddColumn(ActualFiles, "Data", each
        Csv.Document(
            [Content],
            [Delimiter=",", Columns=4, Encoding=65001, QuoteStyle=QuoteStyle.None]
        )
    ),
    ExpandData = Table.ExpandTableColumn(LoadCSV, "Data",
        {"Column1","Column2","Column3","Column4"},
        {"date","branch_id","account_id","amount"}
    ),

    // Promote headers (first file's first row becomes header — skip it)
    RemoveHeaders = Table.SelectRows(ExpandData, each [date] <> "date"),

    // Select only needed columns
    KeepCols = Table.SelectColumns(RemoveHeaders, {"date","branch_id","account_id","amount"}),

    // Type each column correctly
    TypedTable = Table.TransformColumnTypes(KeepCols, {
        {"date",       type date},
        {"branch_id",  type text},
        {"account_id", Int64.Type},
        {"amount",     type number}
    }),

    // Add derived columns for slicing
    AddYear    = Table.AddColumn(TypedTable, "Year",  each Date.Year([date]),  Int64.Type),
    AddMonth   = Table.AddColumn(AddYear,   "Month", each Date.Month([date]), Int64.Type),
    AddYearMon = Table.AddColumn(AddMonth,  "YearMonth",
                    each Text.PadEnd(Text.From(Date.Year([date])), 4)
                         & "-"
                         & Text.PadStart(Text.From(Date.Month([date])), 2, "0"),
                    type text)
in
    AddYearMon


// ── TABLE 2: fact_Budget ──────────────────────────────────────────────────────
let
    Source = Csv.Document(
        File.Contents("C:\NovaStar\data\budget_monthly.csv"),
        [Delimiter=",", Columns=6, Encoding=65001, QuoteStyle=QuoteStyle.None]
    ),
    PromoteHeaders = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    TypedTable = Table.TransformColumnTypes(PromoteHeaders, {
        {"period",        type text},
        {"year",          Int64.Type},
        {"month",         Int64.Type},
        {"branch_id",     type text},
        {"account_id",    Int64.Type},
        {"budget_amount", type number}
    })
in
    TypedTable


// ── TABLE 3: dim_Account ──────────────────────────────────────────────────────
let
    Source = Excel.Workbook(
        File.Contents("C:\NovaStar\data\PL_Dimensions.xlsx"),
        null, true
    ),
    // The Excel file has two sheets: dim_account and dim_branch
    AccountSheet = Source{[Name="dim_account"]}[Data],
    TypedAccount = Table.TransformColumnTypes(AccountSheet, {
        {"account_id",   Int64.Type},
        {"account_code", type text},
        {"account_name", type text},
        {"category",     type text},
        {"subcategory",  type text},
        {"p_l_sign",     Int64.Type}
    })
in
    TypedAccount


// ── TABLE 4: dim_Branch ───────────────────────────────────────────────────────
let
    Source = Excel.Workbook(
        File.Contents("C:\NovaStar\data\PL_Dimensions.xlsx"),
        null, true
    ),
    BranchSheet = Source{[Name="dim_branch"]}[Data],
    TypedBranch = Table.TransformColumnTypes(BranchSheet, {
        {"branch_id",   type text},
        {"branch_name", type text},
        {"region",      type text},
        {"city",        type text},
        {"branch_type", type text},
        {"opened_year", Int64.Type}
    })
in
    TypedBranch


// ── TABLE 5: dim_Date (generated in M) ───────────────────────────────────────
let
    StartDate = #date(2022, 1, 1),
    EndDate   = #date(2024, 12, 31),

    // Generate list of all dates
    DateCount = Duration.Days(EndDate - StartDate) + 1,
    DateList  = List.Dates(StartDate, DateCount, #duration(1,0,0,0)),

    // Convert to table
    DateTable = Table.FromList(DateList, Splitter.SplitByNothing(), {"Date"}),
    TypeDate  = Table.TransformColumnTypes(DateTable, {{"Date", type date}}),

    // Year
    AddYear        = Table.AddColumn(TypeDate, "Year",
                         each Date.Year([Date]), Int64.Type),
    // Quarter
    AddQuarter     = Table.AddColumn(AddYear,  "Quarter",
                         each "Q" & Text.From(Date.QuarterOfYear([Date])), type text),
    // Month number
    AddMonth       = Table.AddColumn(AddQuarter, "Month",
                         each Date.Month([Date]), Int64.Type),
    // Month name
    AddMonthName   = Table.AddColumn(AddMonth,   "MonthName",
                         each Date.ToText([Date], "MMM"), type text),
    // Year-Month string (e.g. "2024-03")
    AddYearMonth   = Table.AddColumn(AddMonthName, "YearMonth",
                         each Text.From(Date.Year([Date]))
                              & "-"
                              & Text.PadStart(Text.From(Date.Month([Date])), 2, "0"),
                         type text),
    // Day of week name
    AddDayOfWeek   = Table.AddColumn(AddYearMonth, "DayOfWeek",
                         each Date.ToText([Date], "ddd"), type text),
    // IsWeekend flag
    AddIsWeekend   = Table.AddColumn(AddDayOfWeek, "IsWeekend",
                         each Date.DayOfWeek([Date], Day.Monday) >= 5, type logical),
    // IsMonthEnd flag
    AddIsMonthEnd  = Table.AddColumn(AddIsWeekend, "IsMonthEnd",
                         each Date.EndOfMonth([Date]) = [Date], type logical),
    // Fiscal Year (same as calendar for NovaStar)
    AddFiscalYear  = Table.AddColumn(AddIsMonthEnd, "FiscalYear",
                         each "FY" & Text.From(Date.Year([Date])), type text),
    // Fiscal quarter label
    AddFiscalQtr   = Table.AddColumn(AddFiscalYear, "FiscalQuarter",
                         each "FY" & Text.From(Date.Year([Date]))
                              & " Q" & Text.From(Date.QuarterOfYear([Date])), type text),
    // YTD flag for current year (2024)
    AddIsYTD       = Table.AddColumn(AddFiscalQtr, "IsYTD2024",
                         each Date.Year([Date]) = 2024, type logical)
in
    AddIsYTD


// ── RELATIONSHIPS TO SET IN THE MODEL ────────────────────────────────────────
// After loading all tables, create these relationships in Power BI Model view:
//
//  fact_Actual[date]       → dim_Date[Date]        (Many-to-One, Active)
//  fact_Actual[branch_id]  → dim_Branch[branch_id] (Many-to-One, Active)
//  fact_Actual[account_id] → dim_Account[account_id](Many-to-One, Active)
//
//  fact_Budget[branch_id]  → dim_Branch[branch_id] (Many-to-One, Active)
//  fact_Budget[account_id] → dim_Account[account_id](Many-to-One, Active)
//  fact_Budget[year]       → dim_Date[Year]         (Many-to-One, Active)
//  fact_Budget[month]      → dim_Date[Month]        (Many-to-One, Inactive — use for month-level)
//
// Cross-filter direction: Single (fact → dimension) for all relationships
