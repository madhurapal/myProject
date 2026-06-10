"""
seed.py — Generate and load realistic sample data into DuckDB
Produces ~200K fact rows across both solutions (scales with SCALE_FACTOR)

Usage:
    python database/seed.py               # default scale
    python database/seed.py --scale 5     # 5× more data (~1M rows)
    python database/seed.py --reset       # drop and recreate all tables
"""

import duckdb
import random
import argparse
from datetime import date, timedelta
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
DB_PATH      = Path(__file__).parent.parent / "analytics.duckdb"
SCHEMA_PATH  = Path(__file__).parent / "schema.sql"
RANDOM_SEED  = 42
random.seed(RANDOM_SEED)

# ── CLI args ──────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument("--scale",  type=int, default=1, help="Data scale multiplier (default 1 ≈ 200K rows)")
parser.add_argument("--reset",  action="store_true",  help="Drop all tables before seeding")
args = parser.parse_args()

SCALE         = args.scale
N_CUSTOMERS   = 5_000  * SCALE
N_MONTHS      = 24                  # 2 years of monthly snapshots
N_PRODUCTS    = 200    * SCALE
N_SO          = 50_000 * SCALE      # Sales orders
N_INV_SNAPS   = 10_000 * SCALE      # Inventory snapshots


# ── Helpers ───────────────────────────────────────────────────────────────────
def rand_date(start: date, end: date) -> date:
    delta = (end - start).days
    if delta <= 0:
        return start
    return start + timedelta(days=random.randint(0, delta))

def date_key(d: date) -> int:
    return d.year * 10000 + d.month * 100 + d.day

def fiscal_period(d: date) -> str:
    fy = d.year + 1 if d.month >= 4 else d.year
    fq = {1: 4, 2: 4, 3: 4, 4: 1, 5: 1, 6: 1, 7: 2, 8: 2, 9: 2, 10: 3, 11: 3, 12: 3}[d.month]
    return f"FY{fy}-Q{fq}"


# ── Connect ───────────────────────────────────────────────────────────────────
print(f"Connecting to {DB_PATH}...")
con = duckdb.connect(str(DB_PATH))

if args.reset:
    print("Resetting database...")
    tables = [
        "fact_inventory_snapshot", "fact_sales_orders", "fact_gl_entries",
        "fact_monthly_snapshot", "fact_subscriptions",
        "dim_warehouses", "dim_suppliers", "dim_products", "dim_cost_centers",
        "dim_accounts", "dim_segments", "dim_plans", "dim_customers", "dim_date"
    ]
    for t in tables:
        con.execute(f"DROP TABLE IF EXISTS {t}")

con.execute(SCHEMA_PATH.read_text())
print("Schema ready.")


# ── dim_date ──────────────────────────────────────────────────────────────────
print("Seeding dim_date...")
START_DATE = date(2022, 1, 1)
END_DATE   = date(2026, 12, 31)
dates = []
d = START_DATE
while d <= END_DATE:
    fy  = d.year + 1 if d.month >= 4 else d.year
    fq  = {1:4,2:4,3:4,4:1,5:1,6:1,7:2,8:2,9:2,10:3,11:3,12:3}[d.month]
    wk  = d.isocalendar()[1]
    dow = d.strftime("%A")
    ym  = f"{d.year}-{d.month:02d}"
    dates.append((
        date_key(d), d, d.year, (d.month - 1) // 3 + 1,
        d.month, d.strftime("%B"), wk, dow,
        d.weekday() >= 5, fy, fq, ym
    ))
    d += timedelta(days=1)

con.executemany("""
    INSERT OR IGNORE INTO dim_date VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
""", dates)
print(f"  {len(dates)} date rows")

# Build lookup: first day of each month → date_key
month_keys = {}
for row in dates:
    ym = row[11]
    if ym not in month_keys:
        month_keys[ym] = row[0]

all_date_keys = [r[0] for r in dates]


# ── dim_plans ─────────────────────────────────────────────────────────────────
print("Seeding dim_plans...")
plans = [
    (1, "PLN001", "Starter Monthly",    "Monthly", 29.00,  "Basic"),
    (2, "PLN002", "Starter Annual",     "Annual",  24.00,  "Basic"),
    (3, "PLN003", "Pro Monthly",        "Monthly", 99.00,  "Mid"),
    (4, "PLN004", "Pro Annual",         "Annual",  79.00,  "Mid"),
    (5, "PLN005", "Enterprise Monthly", "Monthly", 299.00, "Premium"),
    (6, "PLN006", "Enterprise Annual",  "Annual",  249.00, "Premium"),
]
con.executemany("INSERT OR IGNORE INTO dim_plans VALUES (?,?,?,?,?,?)", plans)

plan_ids   = [p[0] for p in plans]
plan_price = {p[0]: p[4] for p in plans}
plan_tier  = {p[0]: p[5] for p in plans}


# ── dim_segments ──────────────────────────────────────────────────────────────
print("Seeding dim_segments...")
segments = [
    (1, "SEG001", "SMB",        "Retail",        "1-50"),
    (2, "SEG002", "SMB",        "Technology",    "1-50"),
    (3, "SEG003", "Mid-Market", "Finance",       "51-500"),
    (4, "SEG004", "Mid-Market", "Healthcare",    "51-500"),
    (5, "SEG005", "Enterprise", "Manufacturing", "500+"),
    (6, "SEG006", "Enterprise", "Technology",    "500+"),
]
con.executemany("INSERT OR IGNORE INTO dim_segments VALUES (?,?,?,?,?)", segments)
segment_ids = [s[0] for s in segments]


# ── dim_customers ─────────────────────────────────────────────────────────────
print(f"Seeding dim_customers ({N_CUSTOMERS} rows)...")
first_names  = ["James","Maria","David","Sarah","Michael","Emily","Robert","Jessica","William","Lisa",
                "Daniel","Emma","Matthew","Olivia","Christopher","Sophia","Andrew","Isabella","Joshua","Mia"]
last_names   = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Wilson","Moore",
                "Taylor","Anderson","Thomas","Jackson","White","Harris","Martin","Thompson","Young","Hall"]
countries    = ["USA","UK","Canada","Australia","India","Germany","France","Singapore","Brazil","UAE"]
regions      = ["North","South","East","West","Central"]
cities       = ["New York","London","Toronto","Sydney","Mumbai","Berlin","Paris","Singapore","São Paulo","Dubai"]
age_groups   = ["18-24","25-34","35-44","45-54","55+"]
genders      = ["M","F","Non-Binary"]
channels     = ["Organic","Paid","Referral","Social","Partnership"]

customers = []
for i in range(1, N_CUSTOMERS + 1):
    signup = rand_date(date(2022, 1, 1), date(2025, 6, 30))
    customers.append((
        i,
        f"CUST{i:06d}",
        f"{random.choice(first_names)} {random.choice(last_names)}",
        f"user{i}@example.com",
        random.choice(countries),
        random.choice(regions),
        random.choice(cities),
        signup,
        random.choice(age_groups),
        random.choice(genders),
        random.choice(channels),
    ))
con.executemany("INSERT OR IGNORE INTO dim_customers VALUES (?,?,?,?,?,?,?,?,?,?,?)", customers)
print(f"  {len(customers)} customer rows")


# ── fact_subscriptions + fact_monthly_snapshot ────────────────────────────────
print("Seeding fact_subscriptions + fact_monthly_snapshot...")
churn_reasons = ["Price","Competition","Feature Gap","Support","Scaled Down","Unknown"]

sub_rows      = []
snapshot_rows = []
sub_key       = 1
snap_key      = 1

for cust in customers:
    cust_key   = cust[0]
    signup     = cust[7]
    plan_key   = random.choice(plan_ids)
    seg_key    = random.choice(segment_ids)
    mrr        = plan_price[plan_key] + random.uniform(-5, 20)
    contract   = random.choice([1, 3, 6, 12])
    end_date   = signup + timedelta(days=contract * 30)
    is_churned = random.random() < 0.25  # 25% churn rate
    churn_date = rand_date(signup + timedelta(days=60), end_date) if is_churned else None
    status     = "Churned" if is_churned else "Active"
    reason     = random.choice(churn_reasons) if is_churned else None

    sub_rows.append((
        sub_key, cust_key, plan_key, seg_key,
        date_key(signup),
        date_key(end_date) if is_churned else None,
        status, reason, round(mrr, 2), contract,
        is_churned, False,
        date_key(churn_date) if churn_date else None
    ))
    sub_key += 1

    # Monthly snapshots for this customer
    cumulative = 0.0
    for m in range(N_MONTHS):
        snap_date  = date(signup.year + (signup.month + m - 1) // 12,
                          (signup.month + m - 1) % 12 + 1, 1)
        if snap_date > date(2026, 6, 30):
            break
        dk = date_key(snap_date)
        if dk not in {r[0] for r in dates}:
            continue
        snap_churned = is_churned and churn_date and snap_date >= churn_date.replace(day=1)
        logins   = 0 if snap_churned else random.randint(0, 30)
        usage    = round(random.uniform(0, 30) if snap_churned else random.uniform(20, 100), 2)
        tickets  = random.randint(0, 8)
        cumulative += mrr
        cohort_dk = date_key(signup.replace(day=1))

        snapshot_rows.append((
            snap_key, cust_key, plan_key, seg_key,
            dk, cohort_dk,
            "Churned" if snap_churned else "Active",
            round(mrr, 2), round(cumulative, 2),
            tickets, logins, usage,
            snap_churned, m
        ))
        snap_key += 1

con.executemany("""
    INSERT OR IGNORE INTO fact_subscriptions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
""", sub_rows)
con.executemany("""
    INSERT OR IGNORE INTO fact_monthly_snapshot VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
""", snapshot_rows)
print(f"  {len(sub_rows)} subscription rows, {len(snapshot_rows)} snapshot rows")


# ── dim_accounts ──────────────────────────────────────────────────────────────
print("Seeding dim_accounts...")
accounts = [
    (1,  "4000","Product Revenue",       "Revenue","Net Revenue",  "Product Revenue",      False, 10),
    (2,  "4010","Service Revenue",       "Revenue","Net Revenue",  "Service Revenue",      False, 20),
    (3,  "4020","Subscription Revenue",  "Revenue","Net Revenue",  "Subscription Revenue", False, 30),
    (4,  "4090","Returns & Discounts",   "Revenue","Net Revenue",  "Less: Returns",        True,  40),
    (5,  "5000","Direct Material Cost",  "COGS",   "Gross Profit", "COGS - Materials",     True,  60),
    (6,  "5010","Direct Labor Cost",     "COGS",   "Gross Profit", "COGS - Labor",         True,  70),
    (7,  "5020","Freight & Logistics",   "COGS",   "Gross Profit", "COGS - Freight",       True,  80),
    (8,  "6000","Sales Compensation",    "OpEx",   "EBITDA",       "Sales & Marketing",    True,  120),
    (9,  "6010","Marketing Spend",       "OpEx",   "EBITDA",       "Sales & Marketing",    True,  130),
    (10, "6020","R&D Expenses",          "OpEx",   "EBITDA",       "R&D",                  True,  140),
    (11, "6030","G&A Expenses",          "OpEx",   "EBITDA",       "G&A",                  True,  150),
    (12, "7000","Depreciation",          "OpEx",   "Net Income",   "D&A",                  True,  180),
    (13, "7020","Interest Expense",      "Other",  "Net Income",   "Interest",             True,  200),
    (14, "8000","Income Tax Expense",    "Other",  "Net Income",   "Tax",                  True,  210),
]
con.executemany("INSERT OR IGNORE INTO dim_accounts VALUES (?,?,?,?,?,?,?,?)", accounts)
acct_ids = [a[0] for a in accounts]
acct_type = {a[0]: a[3] for a in accounts}


# ── dim_cost_centers ──────────────────────────────────────────────────────────
print("Seeding dim_cost_centers...")
cost_centers = [
    (1, "CC001","Sales - North America","Sales",      "Commercial","North America"),
    (2, "CC002","Sales - EMEA",         "Sales",      "Commercial","EMEA"),
    (3, "CC003","Marketing",            "Marketing",  "Commercial","Global"),
    (4, "CC004","Engineering",          "Engineering","Product",   "Global"),
    (5, "CC005","G&A",                  "G&A",        "Corporate", "Global"),
    (6, "CC006","Supply Chain",         "Operations", "Operations","APAC"),
]
con.executemany("INSERT OR IGNORE INTO dim_cost_centers VALUES (?,?,?,?,?,?)", cost_centers)
cc_ids = [c[0] for c in cost_centers]


# ── dim_products ──────────────────────────────────────────────────────────────
print(f"Seeding dim_products ({N_PRODUCTS} rows)...")
categories    = ["Electronics","Apparel","Home & Garden","Sports","Food & Beverage"]
sub_cats      = {"Electronics":["Laptops","Phones","Accessories"],
                 "Apparel":["Tops","Bottoms","Footwear"],
                 "Home & Garden":["Furniture","Decor","Tools"],
                 "Sports":["Equipment","Clothing","Nutrition"],
                 "Food & Beverage":["Snacks","Beverages","Fresh"]}
brands        = ["AlphaBrand","BetaCo","GammaTech","DeltaGoods","EpsilonMart"]

products = []
for i in range(1, N_PRODUCTS + 1):
    cat  = random.choice(categories)
    sub  = random.choice(sub_cats[cat])
    cost = round(random.uniform(5, 200), 2)
    price= round(cost * random.uniform(1.3, 2.5), 2)
    gm   = round((price - cost) / price * 100, 2)
    products.append((i, f"PROD{i:04d}", f"{sub} Item {i}", cat, sub,
                     random.choice(brands), cost, price, gm))
con.executemany("INSERT OR IGNORE INTO dim_products VALUES (?,?,?,?,?,?,?,?,?)", products)
prod_ids = [p[0] for p in products]
prod_cost  = {p[0]: p[6] for p in products}
prod_price = {p[0]: p[7] for p in products}


# ── dim_suppliers ─────────────────────────────────────────────────────────────
print("Seeding dim_suppliers...")
suppliers = [
    (1,"SUP001","Acme Manufacturing","USA","North America",7, 92.5,"Electronics"),
    (2,"SUP002","Global Textiles Ltd","India","APAC",       14,88.0,"Apparel"),
    (3,"SUP003","Pacific Goods Co",  "China","APAC",        21,75.0,"Home & Garden"),
    (4,"SUP004","Euro Parts GmbH",   "Germany","EMEA",      10,95.0,"Electronics"),
    (5,"SUP005","Southern Foods Inc","Brazil","LATAM",       5,90.0,"Food & Beverage"),
]
con.executemany("INSERT OR IGNORE INTO dim_suppliers VALUES (?,?,?,?,?,?,?,?)", suppliers)
sup_ids = [s[0] for s in suppliers]


# ── dim_warehouses ────────────────────────────────────────────────────────────
print("Seeding dim_warehouses...")
warehouses = [
    (1,"WH001","East Coast DC",   "USA",       "North America",False),
    (2,"WH002","West Coast DC",   "USA",       "North America",False),
    (3,"WH003","UK Fulfilment",   "UK",        "EMEA",         True),
    (4,"WH004","APAC Hub",        "Singapore", "APAC",         False),
    (5,"WH005","Central Europe DC","Germany",  "EMEA",         False),
]
con.executemany("INSERT OR IGNORE INTO dim_warehouses VALUES (?,?,?,?,?,?)", warehouses)
wh_ids  = [w[0] for w in warehouses]


# ── fact_gl_entries ───────────────────────────────────────────────────────────
print("Seeding fact_gl_entries (Actual + Budget)...")
gl_rows = []
gl_key  = 1
revenue_accts = [a[0] for a in accounts if a[3] == "Revenue"]
cogs_accts    = [a[0] for a in accounts if a[3] == "COGS"]
opex_accts    = [a[0] for a in accounts if a[3] == "OpEx"]

for yr in [2024, 2025, 2026]:
    for mo in range(1, 13):
        if date(yr, mo, 1) > date(2026, 6, 30):
            break
        period_date = date(yr, mo, 15)
        dk          = date_key(period_date)
        fp          = fiscal_period(period_date)

        for scenario in ["Actual", "Budget"]:
            noise = 1.0 if scenario == "Budget" else random.uniform(0.85, 1.15)

            # Revenue
            for acct_key in revenue_accts:
                base = random.uniform(80_000, 500_000)
                gl_rows.append((gl_key, acct_key, random.choice(cc_ids),
                                random.choice(prod_ids), dk, fp,
                                f"JNL-{gl_key:06d}", "Monthly posting",
                                round(base * noise, 2), scenario))
                gl_key += 1

            # COGS
            for acct_key in cogs_accts:
                base = random.uniform(30_000, 200_000)
                gl_rows.append((gl_key, acct_key, random.choice(cc_ids),
                                random.choice(prod_ids), dk, fp,
                                f"JNL-{gl_key:06d}", "Monthly COGS",
                                round(base * noise, 2), scenario))
                gl_key += 1

            # OpEx
            for acct_key in opex_accts:
                base = random.uniform(10_000, 80_000)
                gl_rows.append((gl_key, acct_key, random.choice(cc_ids),
                                None, dk, fp,
                                f"JNL-{gl_key:06d}", "Monthly OpEx",
                                round(base * noise, 2), scenario))
                gl_key += 1

con.executemany("""
    INSERT OR IGNORE INTO fact_gl_entries VALUES (?,?,?,?,?,?,?,?,?,?)
""", gl_rows)
print(f"  {len(gl_rows)} GL entry rows")


# ── fact_sales_orders ─────────────────────────────────────────────────────────
print(f"Seeding fact_sales_orders ({N_SO} rows)...")
so_rows = []
for i in range(1, N_SO + 1):
    prod_key  = random.choice(prod_ids)
    order_dt  = rand_date(date(2023, 1, 1), date(2026, 6, 30))
    promise_dt= order_dt + timedelta(days=random.choice([3, 5, 7, 14]))
    actual_dt = promise_dt + timedelta(days=random.randint(-2, 7))
    qty       = random.randint(1, 100)
    uprice    = prod_price[prod_key]
    ucost     = prod_cost[prod_key]
    disc      = round(uprice * qty * random.uniform(0, 0.15), 2)
    net_rev   = round(uprice * qty - disc, 2)
    cogs_val  = round(ucost * qty, 2)
    gp        = round(net_rev - cogs_val, 2)
    on_time   = actual_dt <= promise_dt
    in_full   = random.random() > 0.05
    ret_qty   = random.randint(0, max(1, qty // 10)) if random.random() < 0.05 else 0

    so_rows.append((
        i, prod_key, random.choice(sup_ids), random.choice(wh_ids), random.choice(cc_ids),
        date_key(order_dt), date_key(promise_dt), date_key(actual_dt),
        f"SO{i:07d}", qty, uprice, ucost, net_rev, cogs_val, gp, disc,
        on_time and in_full, on_time, in_full,
        ret_qty, round(ret_qty * uprice, 2)
    ))

con.executemany("""
    INSERT OR IGNORE INTO fact_sales_orders VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
""", so_rows)
print(f"  {len(so_rows)} sales order rows")


# ── fact_inventory_snapshot ───────────────────────────────────────────────────
print(f"Seeding fact_inventory_snapshot ({N_INV_SNAPS} rows)...")
inv_rows = []
sample_dates = [date_key(date(2025, m, 1)) for m in range(1, 13)] + \
               [date_key(date(2026, m, 1)) for m in range(1, 7)]

for i in range(1, N_INV_SNAPS + 1):
    prod_key = random.choice(prod_ids)
    ucost    = prod_cost[prod_key]
    qoh      = random.randint(0, 500)
    qoo      = random.randint(0, 100)
    reorder  = random.randint(20, 80)
    avail    = max(0, qoh - random.randint(0, 20))
    dos      = round(qoh / max(1, random.randint(5, 30)), 2)
    stockout = qoh == 0
    below_ro = qoh < reorder

    inv_rows.append((
        i, prod_key, random.choice(wh_ids), random.choice(sup_ids),
        random.choice(sample_dates),
        qoh, qoo, avail, ucost,
        round(qoh * ucost, 2), reorder,
        below_ro, dos, stockout
    ))

con.executemany("""
    INSERT OR IGNORE INTO fact_inventory_snapshot VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
""", inv_rows)
print(f"  {len(inv_rows)} inventory rows")


# ── Summary ───────────────────────────────────────────────────────────────────
con.close()
total = (len(dates) + len(customers) + len(sub_rows) + len(snapshot_rows) +
         len(gl_rows) + len(so_rows) + len(inv_rows))
print(f"\n✅  Seed complete — {total:,} total rows written to {DB_PATH}")
print(f"   fact_monthly_snapshot : {len(snapshot_rows):>8,}")
print(f"   fact_gl_entries       : {len(gl_rows):>8,}")
print(f"   fact_sales_orders     : {len(so_rows):>8,}")
print(f"   fact_inventory_snapshot:{len(inv_rows):>7,}")
