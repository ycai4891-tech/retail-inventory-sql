# Multi-Branch Retail Inventory Database

A relational inventory system for a five-branch retailer: schema design with
enforced constraints, plus ten analytical SQL queries covering ABC
classification, stock turn, supplier reliability, inter-branch imbalance and
stock-count variance.

Built as an analytical extension of **Relational Database Design (AC51049)**,
MSc Business Analytics and Financial Technology, University of Dundee.

**[Open `retail_inventory_sql.ipynb` in Google Colab](https://colab.research.google.com/)**
&mdash; runs end to end with no setup beyond one `pip install`.

---

## The problem

A retailer with five branches running stock control on paper or on five separate
spreadsheets has no reliable way to answer basic questions. How much of this
product do we hold across the estate? Which branch is short while another is
sitting on surplus? Which supplier's lead time is actually driving our safety
stock?

Those questions are not hard to answer. They are impossible to answer reliably
when each branch maintains its own product list, because the same item exists as
three codes with three descriptions and nothing prevents it.

This repository is the schema that fixes that, and the queries that demonstrate
what it buys.

## The schema

Eight entities from the original coursework design:

| Entity | Role |
|---|---|
| `Supplier` | Single master record; anchors lead-time and cost analysis |
| `Branch` | Location as a first-class dimension rather than a filename |
| `Employee` | Attribution: every transaction has an owner |
| `Customer` | Links demand to the branch that served it |
| `Product` | The single source of truth for item identity |
| `Inventory` | Product-by-Branch junction; the expected quantity a count is measured against |
| `Order` | Order header, typed as `SALES` or `PURCHASE` |
| `OrderDetails` | Order lines, separated from the header so one order can hold many lines without repeating header data |

Two extensions added after the coursework:

| Entity | Why |
|---|---|
| `StockCount` | Enables measurement of count-versus-system variance |
| `InventoryMovement` | The event log. A position-only table can show that stock is wrong; only a movement log can show whether it went to waste, to an unexplained adjustment, or out of the door |

### Constraint design

Four decisions, each blocking a category of bad data:

- **Composite primary key `(ProductID, BranchID)` on `Inventory`** &mdash; one
  product cannot hold two competing stock rows at the same branch.
- **Foreign keys on every reference** &mdash; stock cannot be recorded against a
  product code or branch that does not exist. A mistyped code fails at write
  time, not at year end.
- **`CHECK (QuantityOnHand >= 0)`** &mdash; negative stock is an accounting
  artefact, not a physical state.
- **`CHECK` on `MovementType`** &mdash; the movement vocabulary is closed, so
  free-text categories cannot creep in and fragment the analysis.

The notebook demonstrates all of these by attempting five realistic data-entry
errors and showing each one refused.

## The queries

| # | Query | Technique |
|---|---|---|
| Q1 | Stock position for one product across all branches | Multi-table join |
| Q2 | Reorder-point breaches, ranked by shortfall | Filtered join, computed sort key |
| Q3 | ABC classification by revenue contribution | CTE + cumulative-sum window function |
| Q3b | A/B/C split of product count against revenue share | Nested aggregate window |
| Q4 | Stock turn and days of cover by branch | CTE, `LEFT JOIN`, `NULLIF` guards |
| Q5 | Supplier lead time, variability and on-time rate | `DATE_DIFF`, `STDDEV_SAMP`, `HAVING` |
| Q6 | Inter-branch imbalance (transfer candidates) | Self-join through two derived tables |
| Q7 | Stock count against system quantity | Join on composite key |
| Q7b | Estate-wide discrepancy rate | Conditional aggregation |
| Q8 | Branch-level demand and average order value | `COUNT(DISTINCT)`, derived metric |
| Q9 | Movement attribution by type | Pivot via conditional aggregation |

Q5 is the one worth reading closely. Average lead time is the headline number,
but `LeadDayVariability` is what actually drives the safety stock a branch has to
carry. In the sample output, one supplier averages 12.7 days with a standard
deviation of 4.4 and hits its promised date 20% of the time, while another
averages 6.6 days with a standard deviation of 0.7 and hits 92.3%. The average
alone would not separate them nearly as clearly.

Q9 is the one that justifies the `InventoryMovement` extension. It pivots
movements into receipts, sales, returns, waste and adjustments per branch, and
expresses waste plus unexplained adjustment as a percentage of goods received.
That is the shrink signal a stock controller is actually measured on, and a
position-only table cannot produce it at all.

## Data

**All data in this repository is synthetic and randomly generated.** No real
retailer's data appears anywhere. The generator uses a fixed seed, so every
figure in the notebook is reproducible.

Three generator choices shape the analysis:

- Demand follows a power law, so ABC classification has a real curve to find.
- Suppliers are given different lead-time means *and* variances, so the
  reliability query can distinguish slow-but-consistent from fast-but-erratic.
- 60% of stock-count lines carry a seeded discrepancy, chosen to sit near the
  59.54% figure that the ECR Retail Loss field study observed across seven
  European retailers and 100 stores. The query recovering that rate validates the
  measurement; it is not a finding about real retail.

## What this schema does not do

- No point-of-sale transaction layer. Sales are modelled as orders. This is the
  largest omission against the ARTS Operational Data Model, the retail industry
  reference design maintained by the Object Management Group.
- No price or promotion history, so a demand spike cannot be attributed to a
  price action.
- No merchandise hierarchy; `Category` is flat where a real model carries
  department, class and subclass.
- `QuantityOnHand` is still stored rather than derived from the movement log, so
  the two can still disagree.
- It is an OLTP schema, normalised for transaction processing and deliberately
  unsuited to reporting at volume. The next build is a separate dimensional
  layer with a periodic snapshot fact table and type-2 slowly changing
  dimensions.
- No indexing or query-plan work. At this data volume it would not be
  measurable, and claiming it would be dishonest.

## Running it

```bash
pip install duckdb pandas
jupyter notebook retail_inventory_sql.ipynb
```

Or open the notebook in Google Colab, where the only dependency installs in the
first cell. DuckDB runs in-process with no server, and enforces primary keys,
foreign keys and `CHECK` constraints, which is why it was chosen over SQLite.

## References

- Rekik, Y., Syntetos, A. and Glock, C. (2020). *Measuring the Sales Impact of
  Improving Inventory Records.* ECR Retail Loss.
- Object Management Group, Retail Domain Technology Committee. *ARTS Operational
  Data Model*, version 7.3.

## Further reading

Two research notes written alongside this project. Every figure in them is a
published third-party benchmark, attributed in full; none is a measured outcome of
this schema.

**`Cai_Research_Note_1_Cost_of_Unstructured_Inventory_Data.pdf`** — the business
case. Reviews the evidence on how inaccurate retail inventory records actually
are, drawing on an ECR Retail Loss field study across seven European retailers and
100 stores (59.54% of audited SKUs carried a discrepancy), a peer-reviewed paper in
the *International Journal of Production Economics* covering 81 stores, and IHL
Group's estimate of $1.73tn in global inventory distortion. Sets out which failure
modes a relational model removes and, importantly, which it does not.

**`Cai_Research_Note_2_Retail_Inventory_Data_Architecture.pdf`** — the technical
note. Benchmarks this eight-entity schema against the ARTS Operational Data Model,
maps where it matches the standard and where it is thinner, and works through the
analytics the model supports. Section 5 proposes the movement-event and
stock-count extensions that are implemented in the notebook here.
