"""
build_dashboard.py — Query DuckDB and render the HTML dashboard.

Usage:
    python pipeline/build_dashboard.py
    python pipeline/build_dashboard.py --output docs/index.html  # GitHub Pages path

The script injects all query results as JSON into the HTML template,
producing a fully self-contained dashboard with no external data calls.
"""

import json
import sys
import argparse
from pathlib import Path
from datetime import datetime

# Add project root to path so imports work from any working directory
sys.path.insert(0, str(Path(__file__).parent.parent))

from connectors.db_connector import get_connection
from connectors.queries import ChurnQueries, FinanceQueries, SupplyChainQueries

# ── Args ──────────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument("--output", default="docs/index.html", help="Output HTML path")
args = parser.parse_args()
OUTPUT_PATH = Path(args.output)
OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)


# ── Fetch all data ────────────────────────────────────────────────────────────
print("Connecting to database...")
con = get_connection(read_only=True)

print("Running queries...")
data = {
    # Churn
    "churn_monthly":     ChurnQueries.monthly_churn_rate(con).to_dict(orient="records"),
    "churn_cohort":      ChurnQueries.cohort_retention(con).to_dict(orient="records"),
    "churn_mrr":         ChurnQueries.mrr_summary(con).to_dict(orient="records"),
    "churn_reasons":     ChurnQueries.churn_by_reason(con).to_dict(orient="records"),
    "at_risk":           ChurnQueries.at_risk_customers(con).to_dict(orient="records"),
    "mrr_by_segment":    ChurnQueries.mrr_by_segment(con).to_dict(orient="records"),
    # Finance
    "pl_summary":        FinanceQueries.pl_summary(con).to_dict(orient="records"),
    "revenue_trend":     FinanceQueries.revenue_trend(con).to_dict(orient="records"),
    "finance_kpi":       FinanceQueries.kpi_summary(con).to_dict(orient="records"),
    "variance_dept":     FinanceQueries.variance_by_department(con).to_dict(orient="records"),
    # Supply Chain
    "otif":              SupplyChainQueries.otif_summary(con).to_dict(orient="records"),
    "inventory":         SupplyChainQueries.inventory_health(con).to_dict(orient="records"),
    "sc_kpi":            SupplyChainQueries.kpi_summary(con).to_dict(orient="records"),
    "revenue_category":  SupplyChainQueries.revenue_by_category(con).to_dict(orient="records"),
    "generated_at":      datetime.utcnow().isoformat() + "Z",
}
con.close()
print("Queries complete.")


# ── HTML Template (self-contained) ────────────────────────────────────────────
DATA_JSON = json.dumps(data, default=str, indent=None)

HTML = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Power BI Analytics Portfolio — Madhura Pal</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  :root {{
    --blue:   #1F4E79; --lblue:  #2E75B6; --teal:  #17A589;
    --green:  #27AE60; --red:    #E74C3C; --orange:#E67E22;
    --bg:     #F4F6F9; --card:   #FFFFFF; --border:#DEE2E6;
    --text:   #212529; --muted:  #6C757D;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: 'Segoe UI', Arial, sans-serif; background: var(--bg); color: var(--text); }}

  /* Nav */
  nav {{ background: var(--blue); color: #fff; padding: 0 24px;
        display: flex; align-items: center; justify-content: space-between;
        height: 56px; position: sticky; top: 0; z-index: 100; box-shadow: 0 2px 8px rgba(0,0,0,.3); }}
  nav .brand {{ font-size: 1.1rem; font-weight: 700; letter-spacing: .5px; }}
  nav .tabs {{ display: flex; gap: 4px; }}
  nav .tab {{ padding: 8px 18px; border-radius: 4px; cursor: pointer; font-size: .85rem;
              color: rgba(255,255,255,.75); transition: background .2s; border: none; background: transparent; }}
  nav .tab:hover, nav .tab.active {{ background: rgba(255,255,255,.15); color: #fff; }}
  nav .updated {{ font-size: .75rem; opacity: .6; }}

  /* Layout */
  .page {{ display: none; padding: 24px; max-width: 1400px; margin: 0 auto; }}
  .page.active {{ display: block; }}

  /* Section header */
  .section-title {{ font-size: 1.4rem; font-weight: 700; color: var(--blue);
                    border-left: 4px solid var(--lblue); padding-left: 12px;
                    margin: 28px 0 16px; }}

  /* KPI Cards */
  .kpi-row {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
              gap: 16px; margin-bottom: 24px; }}
  .kpi-card {{ background: var(--card); border-radius: 10px; padding: 20px 16px;
               border-top: 4px solid var(--lblue); box-shadow: 0 2px 6px rgba(0,0,0,.06); }}
  .kpi-card .label {{ font-size: .75rem; color: var(--muted); text-transform: uppercase;
                      letter-spacing: .8px; margin-bottom: 8px; }}
  .kpi-card .value {{ font-size: 1.75rem; font-weight: 700; color: var(--blue); }}
  .kpi-card .sub   {{ font-size: .8rem; color: var(--muted); margin-top: 4px; }}
  .kpi-card.green  {{ border-top-color: var(--green); }}
  .kpi-card.green .value {{ color: var(--green); }}
  .kpi-card.teal   {{ border-top-color: var(--teal); }}
  .kpi-card.teal   .value {{ color: var(--teal); }}
  .kpi-card.red    {{ border-top-color: var(--red); }}
  .kpi-card.red    .value  {{ color: var(--red); }}
  .kpi-card.orange {{ border-top-color: var(--orange); }}
  .kpi-card.orange .value {{ color: var(--orange); }}

  /* Charts */
  .chart-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr));
                 gap: 20px; margin-bottom: 24px; }}
  .chart-card {{ background: var(--card); border-radius: 10px; padding: 20px;
                 box-shadow: 0 2px 6px rgba(0,0,0,.06); }}
  .chart-card h3 {{ font-size: .9rem; color: var(--muted); margin-bottom: 14px;
                    font-weight: 600; text-transform: uppercase; letter-spacing: .6px; }}
  .chart-card canvas {{ max-height: 280px; }}

  /* Tables */
  .table-card {{ background: var(--card); border-radius: 10px; padding: 20px;
                 box-shadow: 0 2px 6px rgba(0,0,0,.06); margin-bottom: 24px; overflow-x: auto; }}
  .table-card h3 {{ font-size: .9rem; color: var(--muted); margin-bottom: 14px;
                    font-weight: 600; text-transform: uppercase; letter-spacing: .6px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: .85rem; }}
  th {{ background: var(--blue); color: #fff; padding: 10px 12px; text-align: left;
        font-weight: 600; font-size: .78rem; text-transform: uppercase; letter-spacing: .5px; }}
  td {{ padding: 9px 12px; border-bottom: 1px solid var(--border); }}
  tr:hover td {{ background: #f8f9fa; }}
  .badge {{ display: inline-block; padding: 2px 8px; border-radius: 10px;
            font-size: .72rem; font-weight: 600; }}
  .badge-red    {{ background: #FDEDEC; color: var(--red); }}
  .badge-orange {{ background: #FEF9E7; color: var(--orange); }}
  .badge-green  {{ background: #EAFAF1; color: var(--green); }}
  .badge-blue   {{ background: #EBF5FB; color: var(--lblue); }}

  /* Cohort heatmap */
  #cohortTable td {{ font-size: .78rem; text-align: center; padding: 5px 8px; font-weight: 600; }}
  #cohortTable th {{ font-size: .75rem; text-align: center; }}

  footer {{ text-align: center; padding: 32px; color: var(--muted); font-size: .8rem; }}
</style>
</head>
<body>

<nav>
  <div class="brand">📊 Power BI Analytics Portfolio — Madhura Pal</div>
  <div class="tabs">
    <button class="tab active" onclick="showPage('churn',this)">Customer Churn</button>
    <button class="tab" onclick="showPage('finance',this)">Financial P&amp;L</button>
    <button class="tab" onclick="showPage('supplychain',this)">Supply Chain</button>
  </div>
  <div class="updated" id="updatedAt"></div>
</nav>

<!-- ═══════════════════════════════════════════════════════════════════════ -->
<!-- PAGE 1: CUSTOMER CHURN                                                  -->
<!-- ═══════════════════════════════════════════════════════════════════════ -->
<div id="page-churn" class="page active">
  <h2 class="section-title">Customer Churn Analysis</h2>

  <div class="kpi-row" id="churnKPIs"></div>

  <div class="chart-grid">
    <div class="chart-card">
      <h3>Monthly Churn Rate % (All Tiers)</h3>
      <canvas id="churnRateChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>MRR by Segment &amp; Tier</h3>
      <canvas id="mrrSegmentChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>Churn Reasons Breakdown</h3>
      <canvas id="churnReasonChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>Cohort Retention (Month 0–12)</h3>
      <canvas id="cohortLineChart"></canvas>
    </div>
  </div>

  <div class="table-card">
    <h3>Cohort Retention Heatmap (%)</h3>
    <div id="cohortHeatmap"></div>
  </div>

  <div class="table-card">
    <h3>Top At-Risk Customers</h3>
    <table id="atRiskTable">
      <thead><tr>
        <th>Customer</th><th>Plan</th><th>Segment</th><th>Country</th>
        <th>MRR</th><th>Usage Score</th><th>Logins (30d)</th><th>Tickets</th><th>Risk</th>
      </tr></thead>
      <tbody id="atRiskBody"></tbody>
    </table>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════════════ -->
<!-- PAGE 2: FINANCIAL P&L                                                   -->
<!-- ═══════════════════════════════════════════════════════════════════════ -->
<div id="page-finance" class="page">
  <h2 class="section-title">Financial P&amp;L Variance</h2>

  <div class="kpi-row" id="financeKPIs"></div>

  <div class="chart-grid">
    <div class="chart-card">
      <h3>Revenue Trend — Actual vs Budget</h3>
      <canvas id="revenueChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>OpEx by Department — Actual vs Budget</h3>
      <canvas id="opexChart"></canvas>
    </div>
  </div>

  <div class="table-card">
    <h3>P&amp;L Summary — Latest Period</h3>
    <table id="plTable">
      <thead><tr>
        <th>P&amp;L Line</th><th>Category</th><th>Actual ($)</th>
        <th>Budget ($)</th><th>Variance ($)</th><th>Variance %</th><th>Flag</th>
      </tr></thead>
      <tbody id="plBody"></tbody>
    </table>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════════════ -->
<!-- PAGE 3: SUPPLY CHAIN                                                     -->
<!-- ═══════════════════════════════════════════════════════════════════════ -->
<div id="page-supplychain" class="page">
  <h2 class="section-title">Supply Chain KPI Tracking</h2>

  <div class="kpi-row" id="scKPIs"></div>

  <div class="chart-grid">
    <div class="chart-card">
      <h3>OTIF Rate by Supplier (%)</h3>
      <canvas id="otifChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>Revenue by Product Category</h3>
      <canvas id="revCatChart"></canvas>
    </div>
  </div>

  <div class="table-card">
    <h3>Inventory Health by Category &amp; Region</h3>
    <table id="invTable">
      <thead><tr>
        <th>Category</th><th>Region</th><th>SKU Locations</th>
        <th>Inventory Value ($)</th><th>Total Qty</th>
        <th>Stockouts</th><th>Below Reorder</th><th>Avg Days Supply</th>
      </tr></thead>
      <tbody id="invBody"></tbody>
    </table>
  </div>

  <div class="table-card">
    <h3>OTIF Detail by Supplier</h3>
    <table id="otifTable">
      <thead><tr>
        <th>Supplier</th><th>Country</th><th>Category</th>
        <th>Orders</th><th>OTIF Rate</th><th>On-Time</th><th>In Full</th>
        <th>Revenue ($)</th>
      </tr></thead>
      <tbody id="otifBody"></tbody>
    </table>
  </div>
</div>

<footer>
  Built with DuckDB · Python · Chart.js · GitHub Actions · Deployed to GitHub Pages<br>
  <strong>Madhura Pal</strong> — github.com/madhurapal/myProject
</footer>

<script>
// ── Embedded data ────────────────────────────────────────────────────────────
const DATA = {DATA_JSON};

// ── Utilities ────────────────────────────────────────────────────────────────
const fmt  = (n, dec=0) => n == null ? '—' : Number(n).toLocaleString('en-US', {{minimumFractionDigits:dec, maximumFractionDigits:dec}});
const fmtM = n => n == null ? '—' : '$' + fmt(n/1e6, 2) + 'M';
const fmtK = n => n == null ? '—' : '$' + fmt(n/1e3, 1) + 'K';
const pct  = n => n == null ? '—' : n.toFixed(1) + '%';

// ── Nav ──────────────────────────────────────────────────────────────────────
function showPage(name, btn) {{
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.getElementById('page-' + name).classList.add('active');
  btn.classList.add('active');
}}

// ── Updated timestamp ────────────────────────────────────────────────────────
document.getElementById('updatedAt').textContent =
  'Refreshed: ' + new Date(DATA.generated_at).toLocaleString();

// ── CHART DEFAULTS ───────────────────────────────────────────────────────────
Chart.defaults.font.family = "'Segoe UI', Arial, sans-serif";
Chart.defaults.font.size   = 12;
Chart.defaults.color       = '#6C757D';
const COLORS = ['#2E75B6','#17A589','#E67E22','#8E44AD','#E74C3C','#27AE60','#F39C12','#2980B9'];

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 1: CHURN
// ─────────────────────────────────────────────────────────────────────────────

// KPI cards
(function() {{
  const kpi = DATA.churn_mrr[0] || {{}};
  const cards = [
    {{ label:'Active Customers', value: fmt(kpi.active_customers), sub:'Latest snapshot', cls:'' }},
    {{ label:'Total MRR',        value: fmtK(kpi.total_mrr),       sub:'Monthly Recurring Revenue', cls:'teal' }},
    {{ label:'Total ARR',        value: fmtM(kpi.total_arr),       sub:'Annual Recurring Revenue', cls:'green' }},
    {{ label:'Avg Engagement',   value: pct(kpi.avg_engagement),   sub:'Feature usage score', cls:'orange' }},
    {{ label:'Avg Tenure',       value: fmt(kpi.avg_tenure_months, 1) + ' mo', sub:'Customer tenure', cls:'' }},
  ];
  const ct = (DATA.churn_monthly[0] || {{}});
  const churnRt = DATA.churn_monthly.filter(r=>r.tier).reduce((a,r)=>{{
    return {{...a, [r.year_month + '_' + r.tier]: r.churn_rate_pct}};
  }}, {{}});
  const lastPct = DATA.churn_monthly.length ? DATA.churn_monthly[DATA.churn_monthly.length-1].churn_rate_pct : null;
  cards.push({{ label:'Latest Churn Rate', value: pct(lastPct), sub:'Most recent month', cls: lastPct>15?'red':'green' }});

  document.getElementById('churnKPIs').innerHTML = cards.map(c =>
    `<div class="kpi-card ${{c.cls}}"><div class="label">${{c.label}}</div>
     <div class="value">${{c.value}}</div><div class="sub">${{c.sub}}</div></div>`
  ).join('');
}})();

// Monthly churn rate line chart
(function() {{
  const grouped = {{}};
  DATA.churn_monthly.forEach(r => {{
    if (!grouped[r.tier]) grouped[r.tier] = [];
    grouped[r.tier].push({{ x: r.year_month, y: r.churn_rate_pct }});
  }});
  const labels = [...new Set(DATA.churn_monthly.map(r=>r.year_month))].sort();
  const datasets = Object.entries(grouped).map(([tier, pts], i) => ({{
    label: tier, data: labels.map(l => pts.find(p=>p.x===l)?.y ?? null),
    borderColor: COLORS[i], backgroundColor: COLORS[i]+'22',
    tension: 0.4, fill: false, pointRadius: 3
  }}));
  new Chart(document.getElementById('churnRateChart'), {{
    type: 'line',
    data: {{ labels, datasets }},
    options: {{ plugins: {{ legend: {{ position:'bottom' }} }},
               scales: {{ y: {{ title:{{display:true,text:'Churn Rate %'}} }} }} }}
  }});
}})();

// MRR by segment bar chart
(function() {{
  const segs = [...new Set(DATA.mrr_by_segment.map(r=>r.segment_name))];
  const tiers = [...new Set(DATA.mrr_by_segment.map(r=>r.tier))];
  const datasets = tiers.map((t,i) => ({{
    label: t,
    data: segs.map(s => DATA.mrr_by_segment.find(r=>r.segment_name===s&&r.tier===t)?.total_mrr ?? 0),
    backgroundColor: COLORS[i]
  }}));
  new Chart(document.getElementById('mrrSegmentChart'), {{
    type: 'bar',
    data: {{ labels: segs, datasets }},
    options: {{ plugins:{{legend:{{position:'bottom'}}}}, scales:{{x:{{stacked:true}},y:{{stacked:true}}}} }}
  }});
}})();

// Churn reasons doughnut
(function() {{
  new Chart(document.getElementById('churnReasonChart'), {{
    type: 'doughnut',
    data: {{
      labels: DATA.churn_reasons.map(r=>r.churn_reason),
      datasets: [{{ data: DATA.churn_reasons.map(r=>r.churned_count),
                   backgroundColor: COLORS, borderWidth: 2 }}]
    }},
    options: {{ plugins:{{legend:{{position:'right'}}}} }}
  }});
}})();

// Cohort line chart (avg across cohorts)
(function() {{
  const byMonth = {{}};
  DATA.churn_cohort.forEach(r => {{
    const m = r.months_since_start;
    if (!byMonth[m]) byMonth[m] = [];
    byMonth[m].push(r.retention_pct);
  }});
  const months = Object.keys(byMonth).map(Number).sort((a,b)=>a-b);
  const avgRetention = months.map(m => {{
    const arr = byMonth[m];
    return arr.reduce((s,v)=>s+v,0)/arr.length;
  }});
  new Chart(document.getElementById('cohortLineChart'), {{
    type: 'line',
    data: {{
      labels: months.map(m => 'M+' + m),
      datasets: [{{ label:'Avg Retention %', data: avgRetention,
                   borderColor: '#2E75B6', backgroundColor: '#2E75B622',
                   fill: true, tension: 0.4, pointRadius: 4 }}]
    }},
    options: {{ plugins:{{legend:{{position:'bottom'}}}},
               scales:{{ y:{{min:0,max:100,title:{{display:true,text:'Retention %'}}}} }} }}
  }});
}})();

// Cohort heatmap table
(function() {{
  const cohorts = [...new Set(DATA.churn_cohort.map(r=>r.cohort_label))].sort().slice(-12);
  const maxMonth = Math.max(...DATA.churn_cohort.map(r=>r.months_since_start));
  const months = Array.from({{length: Math.min(maxMonth+1, 13)}}, (_,i)=>i);

  const lookup = {{}};
  DATA.churn_cohort.forEach(r => {{ lookup[`${{r.cohort_label}}_${{r.months_since_start}}`] = r.retention_pct; }});

  function retColor(v) {{
    if (v==null) return '#f8f9fa';
    const g = Math.round(v * 2.55);
    return `rgb(${{255-g}},${{g}},80)`;
  }}

  let html = '<table id="cohortTable"><thead><tr><th>Cohort</th>' +
    months.map(m=>`<th>M+${{m}}</th>`).join('') + '</tr></thead><tbody>';
  cohorts.forEach(coh => {{
    html += `<tr><td style="font-weight:600;color:#1F4E79">${{coh}}</td>`;
    months.forEach(m => {{
      const v = lookup[`${{coh}}_${{m}}`];
      const bg = retColor(v);
      html += `<td style="background:${{bg}}">${{v!=null ? v.toFixed(0)+'%' : ''}}</td>`;
    }});
    html += '</tr>';
  }});
  html += '</tbody></table>';
  document.getElementById('cohortHeatmap').innerHTML = html;
}})();

// At-risk table
(function() {{
  const riskBadge = r => {{
    const m = {{Critical:'badge-red',High:'badge-red',Medium:'badge-orange',Low:'badge-green'}};
    return `<span class="badge ${{m[r]||'badge-blue'}}">${{r}}</span>`;
  }};
  document.getElementById('atRiskBody').innerHTML = DATA.at_risk.map(r => `
    <tr>
      <td><strong>${{r.full_name}}</strong><br><small style="color:#999">${{r.customer_id}}</small></td>
      <td>${{r.plan_name}}</td><td>${{r.segment_name}}</td><td>${{r.country}}</td>
      <td>${{fmt(r.mrr)}}</td><td>${{pct(r.usage_score)}}</td>
      <td>${{r.logins_last_30d}}</td><td>${{r.support_tickets}}</td>
      <td>${{riskBadge(r.risk_level)}}</td>
    </tr>`).join('');
}})();

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 2: FINANCE
// ─────────────────────────────────────────────────────────────────────────────

// Finance KPI cards
(function() {{
  const kpi = DATA.finance_kpi[0] || {{}};
  const cards = [
    {{ label:'Revenue',      value: fmtM(kpi.revenue),       sub: kpi.fiscal_period, cls:'' }},
    {{ label:'Gross Profit', value: fmtM(kpi.gross_profit),  sub: pct(kpi.gp_margin_pct) + ' GP Margin', cls:'green' }},
    {{ label:'EBITDA',       value: fmtM(kpi.ebitda),        sub: pct(kpi.ebitda_margin_pct) + ' EBITDA Margin', cls:'teal' }},
    {{ label:'GP Margin',    value: pct(kpi.gp_margin_pct),  sub:'Gross Profit / Revenue', cls: kpi.gp_margin_pct>40?'green':'orange' }},
    {{ label:'EBITDA Margin',value: pct(kpi.ebitda_margin_pct), sub:'EBITDA / Revenue', cls: kpi.ebitda_margin_pct>15?'green':'orange' }},
  ];
  document.getElementById('financeKPIs').innerHTML = cards.map(c =>
    `<div class="kpi-card ${{c.cls}}"><div class="label">${{c.label}}</div>
     <div class="value">${{c.value}}</div><div class="sub">${{c.sub}}</div></div>`
  ).join('');
}})();

// Revenue trend chart
(function() {{
  const actual = DATA.revenue_trend.filter(r=>r.scenario==='Actual');
  const budget = DATA.revenue_trend.filter(r=>r.scenario==='Budget');
  const labels = [...new Set(actual.map(r=>r.fiscal_period))].sort().slice(-8);
  new Chart(document.getElementById('revenueChart'), {{
    type: 'bar',
    data: {{
      labels,
      datasets: [
        {{ label:'Actual',  data: labels.map(l=>actual.find(r=>r.fiscal_period===l)?.revenue??0),
           backgroundColor:'#2E75B6', order: 2 }},
        {{ label:'Budget',  data: labels.map(l=>budget.find(r=>r.fiscal_period===l)?.revenue??0),
           type:'line', borderColor:'#E67E22', backgroundColor:'transparent',
           borderDash:[5,5], pointRadius:4, order:1 }}
      ]
    }},
    options:{{ plugins:{{legend:{{position:'bottom'}}}}, scales:{{y:{{title:{{display:true,text:'USD'}}}}}} }}
  }});
}})();

// OpEx by dept chart
(function() {{
  const depts   = [...new Set(DATA.variance_dept.map(r=>r.department))];
  const periods = [...new Set(DATA.variance_dept.map(r=>r.fiscal_period))].sort().slice(-4);
  const actualD = DATA.variance_dept.filter(r=>r.scenario==='Actual');
  const budgetD = DATA.variance_dept.filter(r=>r.scenario==='Budget');
  const datasets = [
    {{ label:'Actual',  data: depts.map(d=>actualD.filter(r=>r.department===d&&periods.includes(r.fiscal_period)).reduce((s,r)=>s+r.amount,0)),  backgroundColor:'#2E75B6' }},
    {{ label:'Budget',  data: depts.map(d=>budgetD.filter(r=>r.department===d&&periods.includes(r.fiscal_period)).reduce((s,r)=>s+r.amount,0)),  backgroundColor:'#AED6F1' }},
  ];
  new Chart(document.getElementById('opexChart'), {{
    type:'bar', data:{{ labels:depts, datasets }},
    options:{{ plugins:{{legend:{{position:'bottom'}}}}, scales:{{y:{{title:{{display:true,text:'USD'}}}}}} }}
  }});
}})();

// P&L table — latest period
(function() {{
  const latestPeriod = [...new Set(DATA.pl_summary.map(r=>r.fiscal_period))].sort().pop();
  const rows = DATA.pl_summary.filter(r=>r.fiscal_period===latestPeriod)
    .sort((a,b)=>a.display_order-b.display_order);
  const flagBadge = (v, acctType) => {{
    const favorable = (acctType==='Revenue'&&v>=0)||(acctType!=='Revenue'&&v<=0);
    return favorable
      ? `<span class="badge badge-green">Favorable</span>`
      : `<span class="badge badge-red">Unfavorable</span>`;
  }};
  document.getElementById('plBody').innerHTML = rows.map(r => `
    <tr>
      <td><strong>${{r.pl_line}}</strong></td>
      <td><span class="badge badge-blue">${{r.pl_category}}</span></td>
      <td>${{fmt(r.actual_signed)}}</td>
      <td>${{fmt(r.budget_signed)}}</td>
      <td style="color:${{r.variance>=0?'#27AE60':'#E74C3C'}};font-weight:600">
        ${{r.variance>=0?'+':''}}${{fmt(r.variance)}}
      </td>
      <td style="color:${{r.variance_pct>=0?'#27AE60':'#E74C3C'}}">${{r.variance_pct!=null?r.variance_pct.toFixed(1)+'%':'—'}}</td>
      <td>${{flagBadge(r.variance, r.account_type)}}</td>
    </tr>`).join('');
}})();

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 3: SUPPLY CHAIN
// ─────────────────────────────────────────────────────────────────────────────

// SC KPI cards
(function() {{
  const kpi = DATA.sc_kpi[0] || {{}};
  const cards = [
    {{ label:'Total Orders',   value: fmt(kpi.total_orders),       sub:'All time',          cls:'' }},
    {{ label:'Total Revenue',  value: fmtM(kpi.total_revenue),     sub:'Net Revenue',       cls:'teal' }},
    {{ label:'GP Margin',      value: pct(kpi.gp_margin_pct),      sub:'Gross Profit %',    cls: kpi.gp_margin_pct>40?'green':'orange' }},
    {{ label:'OTIF Rate',      value: pct(kpi.otif_rate_pct),      sub:'On Time In Full',   cls: kpi.otif_rate_pct>90?'green':'red' }},
    {{ label:'On-Time Rate',   value: pct(kpi.on_time_pct),        sub:'Delivery vs Promise',cls:'' }},
    {{ label:'Return Rate',    value: pct(kpi.return_rate_pct),    sub:'% orders returned', cls: kpi.return_rate_pct<2?'green':'red' }},
  ];
  document.getElementById('scKPIs').innerHTML = cards.map(c =>
    `<div class="kpi-card ${{c.cls}}"><div class="label">${{c.label}}</div>
     <div class="value">${{c.value}}</div><div class="sub">${{c.sub}}</div></div>`
  ).join('');
}})();

// OTIF by supplier bar chart
(function() {{
  const suppliers = [...new Set(DATA.otif.map(r=>r.supplier_name))];
  const otifRates = suppliers.map(s => {{
    const rows = DATA.otif.filter(r=>r.supplier_name===s);
    const total = rows.reduce((s,r)=>s+r.total_orders,0);
    const otif  = rows.reduce((s,r)=>s+r.otif_count,0);
    return total ? +(otif/total*100).toFixed(1) : 0;
  }});
  new Chart(document.getElementById('otifChart'), {{
    type:'bar',
    data:{{ labels:suppliers,
      datasets:[{{ label:'OTIF Rate %', data:otifRates,
        backgroundColor: otifRates.map(v=>v>=90?'#27AE60':v>=80?'#E67E22':'#E74C3C') }}] }},
    options:{{
      plugins:{{legend:{{display:false}}}},
      scales:{{y:{{min:0,max:100,title:{{display:true,text:'OTIF %'}}}},
               x:{{ticks:{{maxRotation:30}}}}}}
    }}
  }});
}})();

// Revenue by category line chart
(function() {{
  const cats   = [...new Set(DATA.revenue_category.map(r=>r.category))];
  const labels = [...new Set(DATA.revenue_category.map(r=>r.year_month))].sort().slice(-12);
  const datasets = cats.map((cat,i) => ({{
    label: cat,
    data: labels.map(l => DATA.revenue_category.find(r=>r.category===cat&&r.year_month===l)?.revenue??0),
    borderColor: COLORS[i], backgroundColor: COLORS[i]+'33',
    tension: 0.3, fill: false, pointRadius: 2
  }}));
  new Chart(document.getElementById('revCatChart'), {{
    type:'line', data:{{ labels, datasets }},
    options:{{ plugins:{{legend:{{position:'bottom'}}}}, scales:{{y:{{title:{{display:true,text:'Revenue USD'}}}}}} }}
  }});
}})();

// Inventory table
(function() {{
  document.getElementById('invBody').innerHTML = DATA.inventory.map(r => `
    <tr>
      <td>${{r.category}}</td><td>${{r.region}}</td><td>${{fmt(r.sku_locations)}}</td>
      <td>${{fmt(r.total_inv_value)}}</td><td>${{fmt(r.total_qty)}}</td>
      <td style="color:${{r.stockouts>0?'#E74C3C':'#27AE60'}};font-weight:600">${{r.stockouts}}</td>
      <td style="color:${{r.below_reorder>0?'#E67E22':'#27AE60'}}">${{r.below_reorder}}</td>
      <td>${{r.avg_days_supply}} days</td>
    </tr>`).join('');
}})();

// OTIF detail table
(function() {{
  document.getElementById('otifBody').innerHTML = DATA.otif.map(r => `
    <tr>
      <td><strong>${{r.supplier_name}}</strong></td>
      <td>${{r.supplier_country}}</td><td>${{r.product_category}}</td>
      <td>${{fmt(r.total_orders)}}</td>
      <td><span class="badge ${{r.otif_rate_pct>=90?'badge-green':r.otif_rate_pct>=80?'badge-orange':'badge-red'}}">
        ${{r.otif_rate_pct}}%</span></td>
      <td>${{r.on_time_count}}</td><td>${{r.in_full_count}}</td>
      <td>${{fmt(r.total_revenue)}}</td>
    </tr>`).join('');
}})();
</script>
</body>
</html>"""

OUTPUT_PATH.write_text(HTML.replace("{DATA_JSON}", DATA_JSON))
print(f"✅  Dashboard written to {OUTPUT_PATH}")
print(f"   Open in browser: file://{OUTPUT_PATH.resolve()}")
