-- Analytical queries against the multi-branch retail inventory schema

-- ============================================================
-- Q1 cross-branch stock position
-- ============================================================
SELECT  b.BranchName, i.QuantityOnHand, i.ReorderPoint,
        i.QuantityOnHand - i.ReorderPoint AS Headroom
FROM    Inventory i
JOIN    Branch  b ON b.BranchID  = i.BranchID
JOIN    Product p ON p.ProductID = i.ProductID
WHERE   p.SKU = 'SKU-10042'
ORDER BY Headroom;

-- ============================================================
-- Q2 reorder-point breaches
-- ============================================================
SELECT  b.BranchName, p.SKU, p.ProductName,
        i.QuantityOnHand, i.ReorderPoint,
        i.ReorderPoint - i.QuantityOnHand AS Shortfall
FROM    Inventory i
JOIN    Branch  b ON b.BranchID  = i.BranchID
JOIN    Product p ON p.ProductID = i.ProductID
WHERE   i.QuantityOnHand < i.ReorderPoint
ORDER BY Shortfall DESC
LIMIT 10;

-- ============================================================
-- Q3 ABC classification
-- ============================================================
WITH line_value AS (
    SELECT od.ProductID, SUM(od.Quantity * od.UnitPrice) AS Revenue
    FROM   OrderDetails od
    JOIN   "Order" o ON o.OrderID = od.OrderID
    WHERE  o.OrderType = 'SALES'
      AND  o.OrderDate >= DATE '2025-09-01'
    GROUP BY od.ProductID
),
ranked AS (
    SELECT ProductID, Revenue,
           SUM(Revenue) OVER (ORDER BY Revenue DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           / SUM(Revenue) OVER () AS CumulativeShare
    FROM   line_value
)
SELECT  p.SKU, p.ProductName, ROUND(r.Revenue,2) AS Revenue,
        ROUND(r.CumulativeShare*100,1) AS CumPct,
        CASE WHEN r.CumulativeShare <= 0.80 THEN 'A'
             WHEN r.CumulativeShare <= 0.95 THEN 'B'
             ELSE 'C' END AS ABCClass
FROM    ranked r JOIN Product p ON p.ProductID = r.ProductID
ORDER BY r.Revenue DESC
LIMIT 12;

-- ============================================================
-- Q3b ABC summary
-- ============================================================
WITH line_value AS (
    SELECT od.ProductID, SUM(od.Quantity*od.UnitPrice) AS Revenue
    FROM OrderDetails od JOIN "Order" o ON o.OrderID = od.OrderID
    WHERE o.OrderType='SALES' GROUP BY od.ProductID),
ranked AS (
    SELECT ProductID, Revenue,
           SUM(Revenue) OVER (ORDER BY Revenue DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           / SUM(Revenue) OVER () AS CumulativeShare
    FROM line_value)
SELECT  CASE WHEN CumulativeShare<=0.80 THEN 'A'
             WHEN CumulativeShare<=0.95 THEN 'B' ELSE 'C' END AS ABCClass,
        COUNT(*) AS Products,
        ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS PctOfProducts,
        ROUND(SUM(Revenue),2) AS Revenue,
        ROUND(100.0*SUM(Revenue)/SUM(SUM(Revenue)) OVER (),1) AS PctOfRevenue
FROM ranked GROUP BY 1 ORDER BY 1;

-- ============================================================
-- Q4 stock turn and days of cover
-- ============================================================
WITH sold AS (
    SELECT od.ProductID, o.BranchID, SUM(od.Quantity) AS Units
    FROM   OrderDetails od
    JOIN   "Order" o ON o.OrderID = od.OrderID
    WHERE  o.OrderType = 'SALES'
      AND  o.OrderDate >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY od.ProductID, o.BranchID
)
SELECT  b.BranchName,
        ROUND(SUM(i.QuantityOnHand * p.UnitCost),2)                  AS StockValue,
        ROUND(SUM(COALESCE(s.Units,0) * p.UnitCost),2)               AS COGS_12m,
        ROUND(SUM(COALESCE(s.Units,0) * p.UnitCost)
              / NULLIF(SUM(i.QuantityOnHand * p.UnitCost),0), 2)     AS StockTurn,
        ROUND(365 * SUM(i.QuantityOnHand * p.UnitCost)
              / NULLIF(SUM(COALESCE(s.Units,0) * p.UnitCost),0), 0)  AS DaysOfCover
FROM    Inventory i
JOIN    Branch  b ON b.BranchID  = i.BranchID
JOIN    Product p ON p.ProductID = i.ProductID
LEFT JOIN sold s ON s.ProductID = i.ProductID AND s.BranchID = i.BranchID
GROUP BY b.BranchName
ORDER BY DaysOfCover DESC;

-- ============================================================
-- Q5 supplier lead time and reliability
-- ============================================================
SELECT  s.SupplierName,
        COUNT(*)                                             AS Orders,
        ROUND(AVG(DATE_DIFF('day', o.OrderDate, o.ReceivedDate)),1) AS AvgLeadDays,
        ROUND(STDDEV_SAMP(DATE_DIFF('day', o.OrderDate, o.ReceivedDate)),1)
                                                             AS LeadDayVariability,
        ROUND(100.0*SUM(CASE WHEN o.ReceivedDate <= o.PromisedDate
                             THEN 1 ELSE 0 END)/COUNT(*),1)   AS OnTimePct
FROM    "Order" o
JOIN    Supplier s ON s.SupplierID = o.SupplierID
WHERE   o.OrderType = 'PURCHASE' AND o.ReceivedDate IS NOT NULL
GROUP BY s.SupplierName
HAVING  COUNT(*) >= 5
ORDER BY OnTimePct ASC, LeadDayVariability DESC;

-- ============================================================
-- Q6 inter-branch imbalance
-- ============================================================
SELECT  p.SKU, p.ProductName,
        sh.BranchName AS ShortAt,   sh.QuantityOnHand AS ShortQty,
        su.BranchName AS SurplusAt, su.QuantityOnHand AS SurplusQty
FROM    Product p
JOIN   (SELECT i.ProductID, b.BranchName, i.QuantityOnHand
        FROM Inventory i JOIN Branch b ON b.BranchID = i.BranchID
        WHERE i.QuantityOnHand < i.ReorderPoint) sh ON sh.ProductID = p.ProductID
JOIN   (SELECT i.ProductID, b.BranchName, i.QuantityOnHand
        FROM Inventory i JOIN Branch b ON b.BranchID = i.BranchID
        WHERE i.QuantityOnHand > i.ReorderPoint * 2) su ON su.ProductID = p.ProductID
ORDER BY su.QuantityOnHand - sh.QuantityOnHand DESC
LIMIT 10;

-- ============================================================
-- Q7 count vs system variance
-- ============================================================
SELECT  b.BranchName, p.SKU,
        i.QuantityOnHand AS SystemQty, c.CountedQty,
        c.CountedQty - i.QuantityOnHand AS Variance,
        ROUND(100.0*ABS(c.CountedQty - i.QuantityOnHand)
              / NULLIF(i.QuantityOnHand,0),1) AS VariancePct
FROM    StockCount c
JOIN    Inventory i ON i.ProductID = c.ProductID AND i.BranchID = c.BranchID
JOIN    Branch  b ON b.BranchID  = c.BranchID
JOIN    Product p ON p.ProductID = c.ProductID
WHERE   c.CountedQty <> i.QuantityOnHand
ORDER BY ABS(c.CountedQty - i.QuantityOnHand) DESC
LIMIT 10;

-- ============================================================
-- Q7b discrepancy rate vs the ECR benchmark
-- ============================================================
SELECT  COUNT(*) AS LinesCounted,
        SUM(CASE WHEN c.CountedQty <> i.QuantityOnHand THEN 1 ELSE 0 END) AS Discrepant,
        ROUND(100.0*SUM(CASE WHEN c.CountedQty <> i.QuantityOnHand
                             THEN 1 ELSE 0 END)/COUNT(*),2) AS DiscrepancyPct
FROM    StockCount c
JOIN    Inventory i ON i.ProductID = c.ProductID AND i.BranchID = c.BranchID;

-- ============================================================
-- Q8 branch-level demand
-- ============================================================
SELECT  b.BranchName,
        COUNT(DISTINCT o.CustomerID) AS ActiveCustomers,
        COUNT(DISTINCT o.OrderID)    AS Orders,
        ROUND(SUM(od.Quantity*od.UnitPrice),2) AS Revenue,
        ROUND(SUM(od.Quantity*od.UnitPrice)
              / NULLIF(COUNT(DISTINCT o.OrderID),0),2) AS AvgOrderValue
FROM    "Order" o
JOIN    OrderDetails od ON od.OrderID = o.OrderID
JOIN    Branch b ON b.BranchID = o.BranchID
WHERE   o.OrderType = 'SALES'
GROUP BY b.BranchName
ORDER BY Revenue DESC;

-- ============================================================
-- Q9 movement attribution by type
-- ============================================================
SELECT  b.BranchName,
        SUM(CASE WHEN m.MovementType='RECEIPT'    THEN m.Quantity ELSE 0 END) AS Receipts,
        SUM(CASE WHEN m.MovementType='SALE'       THEN m.Quantity ELSE 0 END) AS Sales,
        SUM(CASE WHEN m.MovementType='RETURN'     THEN m.Quantity ELSE 0 END) AS Returns,
        SUM(CASE WHEN m.MovementType='WASTE'      THEN m.Quantity ELSE 0 END) AS Waste,
        SUM(CASE WHEN m.MovementType='ADJUSTMENT' THEN m.Quantity ELSE 0 END) AS Adjustments,
        ROUND(100.0*ABS(SUM(CASE WHEN m.MovementType IN ('WASTE','ADJUSTMENT')
                                 THEN m.Quantity ELSE 0 END))
              / NULLIF(SUM(CASE WHEN m.MovementType='RECEIPT'
                                THEN m.Quantity ELSE 0 END),0),1) AS UnexplainedPctOfReceipts
FROM    InventoryMovement m
JOIN    Branch b ON b.BranchID = m.BranchID
GROUP BY b.BranchName
ORDER BY UnexplainedPctOfReceipts DESC;
