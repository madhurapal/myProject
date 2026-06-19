// =============================================================================
// FitCore Gym — Power Query M Transformations
// Load these in Power BI Desktop:
//   Home → Transform Data → Advanced Editor → paste each query
// =============================================================================


// =============================================================================
// TABLE 1: Members (from Excel sheet "Member_Data")
// =============================================================================
let
    Source = Excel.Workbook(
        File.Contents("FitCore_Churn_Data.xlsx"), null, true
    ),
    Member_Data_Sheet = Source{[Item="Member_Data", Kind="Sheet"]}[Data],

    // Promote first row as headers
    PromotedHeaders = Table.PromoteHeaders(Member_Data_Sheet, [PromoteAllScalars=true]),

    // Set correct data types
    TypedTable = Table.TransformColumnTypes(PromotedHeaders, {
        {"Member ID",           type text},
        {"Full Name",           type text},
        {"Age Group",           type text},
        {"Gender",              type text},
        {"State",               type text},
        {"Home Location",       type text},
        {"Signup Date",         type date},
        {"Membership Plan",     type text},
        {"Monthly Fee",         type number},
        {"Service Type",        type text},
        {"Tenure Months",       Int64.Type},
        {"Has Personal Trainer",type text},
        {"Favourite Class",     type text},
        {"Referral Source",     type text},
        {"Avg Monthly Visits",  Int64.Type},
        {"Last Visit Days Ago", Int64.Type},
        {"Satisfaction Score",  Int64.Type},
        {"NPS Score",           Int64.Type},
        {"Payment Failures",    Int64.Type},
        {"Is Churned",          type text},
        {"Churn Date",          type date},
        {"Churn Reason",        type text}
    }),

    // Rename columns to remove spaces (cleaner DAX references)
    RenamedColumns = Table.RenameColumns(TypedTable, {
        {"Member ID",           "MemberID"},
        {"Full Name",           "FullName"},
        {"Age Group",           "AgeGroup"},
        {"Home Location",       "HomeLocation"},
        {"Signup Date",         "SignupDate"},
        {"Membership Plan",     "MembershipPlan"},
        {"Monthly Fee",         "MonthlyFee"},
        {"Service Type",        "ServiceType"},
        {"Tenure Months",       "TenureMonths"},
        {"Has Personal Trainer","HasPersonalTrainer"},
        {"Favourite Class",     "FavouriteClass"},
        {"Referral Source",     "ReferralSource"},
        {"Avg Monthly Visits",  "AvgMonthlyVisits"},
        {"Last Visit Days Ago", "LastVisitDaysAgo"},
        {"Satisfaction Score",  "SatisfactionScore"},
        {"NPS Score",           "NPSScore"},
        {"Payment Failures",    "PaymentFailures"},
        {"Is Churned",          "IsChurned"},
        {"Churn Date",          "ChurnDate"},
        {"Churn Reason",        "ChurnReason"}
    }),

    // Add: Churn flag as boolean
    AddChurnFlag = Table.AddColumn(RenamedColumns, "IsChurnedBool",
        each [IsChurned] = "Yes", type logical),

    // Add: Tenure bucket for grouping
    AddTenureBucket = Table.AddColumn(AddChurnFlag, "TenureBucket", each
        if [TenureMonths] <= 3  then "0–3 months"
        else if [TenureMonths] <= 6  then "4–6 months"
        else if [TenureMonths] <= 12 then "7–12 months"
        else if [TenureMonths] <= 24 then "13–24 months"
        else "24+ months",
    type text),

    // Add: Risk score (computed for at-risk flag)
    AddRiskScore = Table.AddColumn(AddTenureBucket, "RiskScore", each
        (if [LastVisitDaysAgo] > 30  then 2 else 0) +
        (if [SatisfactionScore] <= 2 then 3 else 0) +
        (if [NPSScore] < 0           then 2 else 0) +
        (if [PaymentFailures] > 1    then 2 else 0) +
        (if [AvgMonthlyVisits] <= 2  then 1 else 0),
    Int64.Type),

    // Add: Risk tier label
    AddRiskTier = Table.AddColumn(AddRiskScore, "RiskTier", each
        if [RiskScore] >= 6 then "High Risk"
        else if [RiskScore] >= 3 then "Medium Risk"
        else "Low Risk",
    type text),

    // Add: Annual revenue (actual collected before churn)
    AddAnnualRevenue = Table.AddColumn(AddRiskTier, "TotalRevenue", each
        [MonthlyFee] * [TenureMonths],
    type number),

    // Add: Signup Year and Month for cohort analysis
    AddSignupYear  = Table.AddColumn(AddAnnualRevenue, "SignupYear",
        each Date.Year([SignupDate]), Int64.Type),
    AddSignupMonth = Table.AddColumn(AddSignupYear, "SignupMonth",
        each Date.Month([SignupDate]), Int64.Type),
    AddSignupYM    = Table.AddColumn(AddSignupMonth, "SignupYearMonth",
        each Text.From(Date.Year([SignupDate])) & "-"
           & Text.PadStart(Text.From(Date.Month([SignupDate])), 2, "0"),
    type text),

    // Remove any blanks/nulls in key columns
    RemovedBlanks = Table.SelectRows(AddSignupYM,
        each [MemberID] <> null and [MemberID] <> "")

in
    RemovedBlanks


// =============================================================================
// TABLE 2: Churn_Summary (from Excel sheet "Churn_Summary")
// Used for pre-aggregated KPI cards
// =============================================================================
let
    Source = Excel.Workbook(
        File.Contents("FitCore_Churn_Data.xlsx"), null, true
    ),
    Churn_Summary_Sheet = Source{[Item="Churn_Summary", Kind="Sheet"]}[Data],
    PromotedHeaders = Table.PromoteHeaders(Churn_Summary_Sheet, [PromoteAllScalars=true]),
    TypedSummary = Table.TransformColumnTypes(PromotedHeaders, {
        {"Plan",            type text},
        {"Total",           Int64.Type},
        {"Churned",         Int64.Type},
        {"Churn Rate (%)",  type text},
        {"Fee/mo",          type text},
        {"Active MRR",      type text}
    })
in
    TypedSummary


// =============================================================================
// TABLE 3: dim_Date (generated in Power Query — no source file needed)
// =============================================================================
let
    StartDate  = #date(2022, 1, 1),
    EndDate    = #date(2026, 12, 31),
    DateCount  = Duration.Days(EndDate - StartDate) + 1,
    DateList   = List.Dates(StartDate, DateCount, #duration(1, 0, 0, 0)),
    DateTable  = Table.FromList(DateList, Splitter.SplitByNothing(), {"Date"}),
    TypedDate  = Table.TransformColumnTypes(DateTable, {{"Date", type date}}),

    AddYear    = Table.AddColumn(TypedDate,  "Year",       each Date.Year([Date]),             Int64.Type),
    AddQuarter = Table.AddColumn(AddYear,    "Quarter",    each Date.QuarterOfYear([Date]),    Int64.Type),
    AddMonth   = Table.AddColumn(AddQuarter, "MonthNum",   each Date.Month([Date]),            Int64.Type),
    AddMonthNm = Table.AddColumn(AddMonth,   "MonthName",  each Date.MonthName([Date]),        type text),
    AddWeek    = Table.AddColumn(AddMonthNm, "WeekNum",    each Date.WeekOfYear([Date]),       Int64.Type),
    AddDOW     = Table.AddColumn(AddWeek,    "DayOfWeek",  each Date.DayOfWeekName([Date]),    type text),
    AddIsWknd  = Table.AddColumn(AddDOW,     "IsWeekend",
                    each Date.DayOfWeek([Date]) >= 5, type logical),
    AddYM      = Table.AddColumn(AddIsWknd,  "YearMonth",
                    each Text.From(Date.Year([Date])) & "-"
                       & Text.PadStart(Text.From(Date.Month([Date])), 2, "0"), type text),
    AddQLabel  = Table.AddColumn(AddYM,      "QuarterLabel",
                    each "Q" & Text.From(Date.QuarterOfYear([Date]))
                       & " " & Text.From(Date.Year([Date])), type text),
    AddDateKey = Table.AddColumn(AddQLabel,  "DateKey",
                    each Date.Year([Date]) * 10000
                       + Date.Month([Date]) * 100
                       + Date.Day([Date]), Int64.Type)
in
    AddDateKey
