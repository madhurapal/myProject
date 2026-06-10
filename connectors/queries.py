"""
queries.py — All analytical queries returning pandas DataFrames.
Each function is a self-contained query ready to feed the HTML dashboard.

Usage:
    from connectors.queries import ChurnQueries, FinanceQueries, SupplyChainQueries
    con = get_connection()
    df  = ChurnQueries.monthly_churn_rate(con)
"""

import pandas as pd
import duckdb


# =============================================================================
# SOLUTION 1 — CUSTOMER CHURN
# =============================================================================

class ChurnQueries:

    @staticmethod
    def monthly_churn_rate(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Monthly churn rate % by plan tier."""
        return con.execute("""
            SELECT
                dd.year,
                dd.month_num,
                dd.month_name,
                dd.year_month,
                dp.tier,
                COUNT(DISTINCT fms.customer_key)                                   AS total_customers,
                SUM(CASE WHEN fms.is_churned THEN 1 ELSE 0 END)                   AS churned_customers,
                ROUND(
                    SUM(CASE WHEN fms.is_churned THEN 1 ELSE 0 END) * 100.0
                    / NULLIF(COUNT(DISTINCT fms.customer_key), 0), 2
                )                                                                   AS churn_rate_pct,
                ROUND(SUM(fms.mrr), 2)                                             AS total_mrr
            FROM fact_monthly_snapshot fms
            JOIN dim_date  dd ON fms.snapshot_date_key = dd.date_key
            JOIN dim_plans dp ON fms.plan_key          = dp.plan_key
            GROUP BY dd.year, dd.month_num, dd.month_name, dd.year_month, dp.tier
            ORDER BY dd.year, dd.month_num, dp.tier
        """).df()

    @staticmethod
    def cohort_retention(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Cohort retention matrix — % active at each month offset."""
        return con.execute("""
            WITH cohort_base AS (
                SELECT
                    cohort_date_key,
                    months_since_start,
                    COUNT(DISTINCT customer_key) AS active_customers
                FROM fact_monthly_snapshot
                WHERE NOT is_churned
                GROUP BY cohort_date_key, months_since_start
            ),
            cohort_size AS (
                SELECT cohort_date_key, active_customers AS cohort_total
                FROM cohort_base WHERE months_since_start = 0
            ),
            cohort_labels AS (
                SELECT date_key, year_month AS cohort_label
                FROM dim_date
            )
            SELECT
                cl.cohort_label,
                cb.months_since_start,
                cb.active_customers,
                cs.cohort_total,
                ROUND(cb.active_customers * 100.0 / NULLIF(cs.cohort_total, 0), 1) AS retention_pct
            FROM cohort_base cb
            JOIN cohort_size   cs ON cb.cohort_date_key = cs.cohort_date_key
            JOIN cohort_labels cl ON cb.cohort_date_key = cl.date_key
            WHERE cb.months_since_start <= 12
            ORDER BY cl.cohort_label, cb.months_since_start
        """).df()

    @staticmethod
    def mrr_summary(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Total MRR, ARR, active customers — latest snapshot."""
        return con.execute("""
            SELECT
                COUNT(DISTINCT customer_key)                    AS active_customers,
                ROUND(SUM(mrr), 2)                              AS total_mrr,
                ROUND(SUM(mrr) * 12, 2)                         AS total_arr,
                ROUND(AVG(feature_usage_score), 1)              AS avg_engagement,
                ROUND(AVG(months_since_start), 1)               AS avg_tenure_months
            FROM fact_monthly_snapshot
            WHERE snapshot_date_key = (
                SELECT MAX(snapshot_date_key) FROM fact_monthly_snapshot
                WHERE NOT is_churned
            )
            AND NOT is_churned
        """).df()

    @staticmethod
    def churn_by_reason(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Churn reason breakdown with MRR lost."""
        return con.execute("""
            SELECT
                COALESCE(fs.churn_reason, 'Unknown') AS churn_reason,
                COUNT(*)                              AS churned_count,
                ROUND(SUM(fs.mrr), 2)                 AS mrr_lost,
                ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
            FROM fact_subscriptions fs
            WHERE fs.is_churned
            GROUP BY fs.churn_reason
            ORDER BY churned_count DESC
        """).df()

    @staticmethod
    def at_risk_customers(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Top 20 at-risk active customers by MRR × risk score."""
        return con.execute("""
            SELECT
                dc.customer_id,
                dc.full_name,
                dp.plan_name,
                ds.segment_name,
                dc.country,
                ROUND(fms.mrr, 2)                   AS mrr,
                ROUND(fms.feature_usage_score, 1)   AS usage_score,
                fms.logins_last_30d,
                fms.support_tickets,
                CASE
                    WHEN fms.feature_usage_score < 20 AND fms.support_tickets > 3 THEN 'Critical'
                    WHEN fms.feature_usage_score < 40 AND fms.logins_last_30d < 5  THEN 'High'
                    WHEN fms.feature_usage_score < 60                               THEN 'Medium'
                    ELSE 'Low'
                END AS risk_level
            FROM fact_monthly_snapshot fms
            JOIN dim_customers dc ON fms.customer_key = dc.customer_key
            JOIN dim_plans     dp ON fms.plan_key     = dp.plan_key
            JOIN dim_segments  ds ON fms.segment_key  = ds.segment_key
            WHERE fms.snapshot_date_key = (
                SELECT MAX(snapshot_date_key) FROM fact_monthly_snapshot WHERE NOT is_churned
            )
            AND NOT fms.is_churned
            ORDER BY fms.feature_usage_score ASC, fms.mrr DESC
            LIMIT 20
        """).df()

    @staticmethod
    def mrr_by_segment(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """MRR breakdown by segment and plan tier."""
        return con.execute("""
            SELECT
                ds.segment_name,
                dp.tier,
                COUNT(DISTINCT fms.customer_key) AS customers,
                ROUND(SUM(fms.mrr), 2)           AS total_mrr
            FROM fact_monthly_snapshot fms
            JOIN dim_segments ds ON fms.segment_key = ds.segment_key
            JOIN dim_plans    dp ON fms.plan_key    = dp.plan_key
            WHERE NOT fms.is_churned
            AND fms.snapshot_date_key = (
                SELECT MAX(snapshot_date_key) FROM fact_monthly_snapshot WHERE NOT is_churned
            )
            GROUP BY ds.segment_name, dp.tier
            ORDER BY total_mrr DESC
        """).df()


# =============================================================================
# SOLUTION 2 — FINANCIAL P&L
# =============================================================================

class FinanceQueries:

    @staticmethod
    def pl_summary(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Full P&L Actual vs Budget by fiscal period."""
        return con.execute("""
            WITH actuals AS (
                SELECT
                    da.pl_category, da.pl_line, da.account_type,
                    da.is_debit_normal, da.display_order,
                    fgl.fiscal_period,
                    SUM(fgl.amount_usd) AS amount
                FROM fact_gl_entries fgl
                JOIN dim_accounts da ON fgl.account_key = da.account_key
                WHERE fgl.scenario = 'Actual'
                GROUP BY da.pl_category, da.pl_line, da.account_type,
                         da.is_debit_normal, da.display_order, fgl.fiscal_period
            ),
            budgets AS (
                SELECT
                    da.pl_category, da.pl_line, da.account_type,
                    fgl.fiscal_period,
                    SUM(fgl.amount_usd) AS budget
                FROM fact_gl_entries fgl
                JOIN dim_accounts da ON fgl.account_key = da.account_key
                WHERE fgl.scenario = 'Budget'
                GROUP BY da.pl_category, da.pl_line, da.account_type, fgl.fiscal_period
            )
            SELECT
                a.pl_category, a.pl_line, a.account_type,
                a.is_debit_normal, a.display_order, a.fiscal_period,
                -- Sign convention: revenue positive, costs negative
                CASE WHEN NOT a.is_debit_normal THEN a.amount ELSE -a.amount END   AS actual_signed,
                CASE WHEN NOT a.is_debit_normal THEN b.budget ELSE -b.budget END   AS budget_signed,
                ROUND(
                    (CASE WHEN NOT a.is_debit_normal THEN a.amount ELSE -a.amount END)
                  - (CASE WHEN NOT a.is_debit_normal THEN COALESCE(b.budget,0) ELSE -COALESCE(b.budget,0) END)
                , 2)                                                                AS variance,
                ROUND(
                    (
                        (CASE WHEN NOT a.is_debit_normal THEN a.amount ELSE -a.amount END)
                      - (CASE WHEN NOT a.is_debit_normal THEN COALESCE(b.budget,0) ELSE -COALESCE(b.budget,0) END)
                    ) * 100.0
                    / NULLIF(ABS(CASE WHEN NOT a.is_debit_normal THEN b.budget ELSE -b.budget END), 0)
                , 2)                                                                AS variance_pct
            FROM actuals a
            LEFT JOIN budgets b
                ON a.pl_line = b.pl_line AND a.fiscal_period = b.fiscal_period
            ORDER BY a.fiscal_period, a.display_order
        """).df()

    @staticmethod
    def revenue_trend(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Monthly revenue trend — Actual vs Budget."""
        return con.execute("""
            SELECT
                fgl.fiscal_period,
                fgl.scenario,
                ROUND(SUM(fgl.amount_usd), 2) AS revenue
            FROM fact_gl_entries fgl
            JOIN dim_accounts da ON fgl.account_key = da.account_key
            WHERE da.account_type = 'Revenue'
            GROUP BY fgl.fiscal_period, fgl.scenario
            ORDER BY fgl.fiscal_period, fgl.scenario
        """).df()

    @staticmethod
    def kpi_summary(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Single-row KPI summary for the latest fiscal period."""
        return con.execute("""
            WITH latest AS (
                SELECT MAX(fiscal_period) AS fp FROM fact_gl_entries WHERE scenario = 'Actual'
            ),
            rev AS (
                SELECT ROUND(SUM(amount_usd),2) AS revenue
                FROM fact_gl_entries fgl JOIN dim_accounts da ON fgl.account_key=da.account_key
                WHERE da.account_type='Revenue' AND fgl.scenario='Actual'
                AND fgl.fiscal_period=(SELECT fp FROM latest)
            ),
            cogs AS (
                SELECT ROUND(SUM(amount_usd),2) AS cogs
                FROM fact_gl_entries fgl JOIN dim_accounts da ON fgl.account_key=da.account_key
                WHERE da.account_type='COGS' AND fgl.scenario='Actual'
                AND fgl.fiscal_period=(SELECT fp FROM latest)
            ),
            opex AS (
                SELECT ROUND(SUM(amount_usd),2) AS opex
                FROM fact_gl_entries fgl JOIN dim_accounts da ON fgl.account_key=da.account_key
                WHERE da.account_type='OpEx' AND fgl.scenario='Actual'
                AND fgl.fiscal_period=(SELECT fp FROM latest)
            )
            SELECT
                (SELECT fp FROM latest)          AS fiscal_period,
                rev.revenue,
                cogs.cogs,
                rev.revenue - cogs.cogs          AS gross_profit,
                ROUND((rev.revenue - cogs.cogs) * 100.0 / NULLIF(rev.revenue,0), 1) AS gp_margin_pct,
                rev.revenue - cogs.cogs - opex.opex  AS ebitda,
                ROUND((rev.revenue - cogs.cogs - opex.opex) * 100.0 / NULLIF(rev.revenue,0), 1) AS ebitda_margin_pct
            FROM rev, cogs, opex
        """).df()

    @staticmethod
    def variance_by_department(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """OpEx variance by department — actual vs budget."""
        return con.execute("""
            SELECT
                dcc.department,
                fgl.fiscal_period,
                fgl.scenario,
                ROUND(SUM(fgl.amount_usd), 2) AS amount
            FROM fact_gl_entries fgl
            JOIN dim_accounts     da  ON fgl.account_key     = da.account_key
            JOIN dim_cost_centers dcc ON fgl.cost_center_key = dcc.cost_center_key
            WHERE da.account_type = 'OpEx'
            GROUP BY dcc.department, fgl.fiscal_period, fgl.scenario
            ORDER BY fgl.fiscal_period, dcc.department
        """).df()


# =============================================================================
# SOLUTION 2 — SUPPLY CHAIN
# =============================================================================

class SupplyChainQueries:

    @staticmethod
    def otif_summary(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """OTIF rate by supplier and product category."""
        return con.execute("""
            SELECT
                ds.supplier_name,
                ds.country              AS supplier_country,
                dp.category             AS product_category,
                COUNT(*)                AS total_orders,
                SUM(CASE WHEN fso.is_otif   THEN 1 ELSE 0 END) AS otif_count,
                SUM(CASE WHEN fso.is_on_time THEN 1 ELSE 0 END) AS on_time_count,
                SUM(CASE WHEN fso.is_in_full THEN 1 ELSE 0 END) AS in_full_count,
                ROUND(SUM(CASE WHEN fso.is_otif THEN 1 ELSE 0 END) * 100.0
                    / NULLIF(COUNT(*), 0), 2)                   AS otif_rate_pct,
                ROUND(SUM(fso.net_revenue), 2)                  AS total_revenue,
                ROUND(SUM(fso.gross_profit), 2)                 AS total_gp
            FROM fact_sales_orders fso
            JOIN dim_suppliers ds ON fso.supplier_key = ds.supplier_key
            JOIN dim_products  dp ON fso.product_key  = dp.product_key
            GROUP BY ds.supplier_name, ds.country, dp.category
            ORDER BY otif_rate_pct ASC
        """).df()

    @staticmethod
    def inventory_health(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Inventory health by product category and warehouse."""
        return con.execute("""
            SELECT
                dp.category,
                dw.region,
                COUNT(*)                                        AS sku_locations,
                ROUND(SUM(fis.inventory_value), 2)             AS total_inv_value,
                SUM(fis.quantity_on_hand)                       AS total_qty,
                SUM(CASE WHEN fis.stockout_flag THEN 1 ELSE 0 END)      AS stockouts,
                SUM(CASE WHEN fis.is_below_reorder THEN 1 ELSE 0 END)   AS below_reorder,
                ROUND(AVG(fis.days_of_supply), 1)              AS avg_days_supply
            FROM fact_inventory_snapshot fis
            JOIN dim_products   dp ON fis.product_key   = dp.product_key
            JOIN dim_warehouses dw ON fis.warehouse_key = dw.warehouse_key
            WHERE fis.snapshot_date_key = (
                SELECT MAX(snapshot_date_key) FROM fact_inventory_snapshot
            )
            GROUP BY dp.category, dw.region
            ORDER BY stockouts DESC, total_inv_value DESC
        """).df()

    @staticmethod
    def kpi_summary(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Overall supply chain KPI headline numbers."""
        return con.execute("""
            SELECT
                COUNT(*)                                        AS total_orders,
                ROUND(SUM(net_revenue), 2)                      AS total_revenue,
                ROUND(SUM(gross_profit), 2)                     AS total_gp,
                ROUND(SUM(gross_profit)*100.0/NULLIF(SUM(net_revenue),0),1) AS gp_margin_pct,
                ROUND(SUM(CASE WHEN is_otif   THEN 1 ELSE 0 END)*100.0/COUNT(*), 2) AS otif_rate_pct,
                ROUND(SUM(CASE WHEN is_on_time THEN 1 ELSE 0 END)*100.0/COUNT(*), 2) AS on_time_pct,
                ROUND(SUM(return_amount),2)                     AS total_returns,
                ROUND(SUM(return_qty)*100.0/NULLIF(SUM(quantity),0),2)      AS return_rate_pct
            FROM fact_sales_orders
        """).df()

    @staticmethod
    def revenue_by_category(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
        """Revenue and GP by product category over time."""
        return con.execute("""
            SELECT
                dp.category,
                dd.year,
                dd.month_num,
                dd.year_month,
                ROUND(SUM(fso.net_revenue), 2)  AS revenue,
                ROUND(SUM(fso.gross_profit), 2) AS gross_profit,
                ROUND(SUM(fso.gross_profit)*100.0/NULLIF(SUM(fso.net_revenue),0),1) AS gp_pct
            FROM fact_sales_orders fso
            JOIN dim_products dp ON fso.product_key   = dp.product_key
            JOIN dim_date     dd ON fso.order_date_key = dd.date_key
            GROUP BY dp.category, dd.year, dd.month_num, dd.year_month
            ORDER BY dd.year, dd.month_num, dp.category
        """).df()
