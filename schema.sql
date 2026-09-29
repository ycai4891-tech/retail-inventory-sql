-- Multi-branch retail inventory schema
-- Relational Database Design (AC51049), analytical extension
-- Target: DuckDB / PostgreSQL. ORDER is a reserved word, hence the quoting.

CREATE TABLE Supplier (
    SupplierID   INTEGER PRIMARY KEY,
    SupplierName VARCHAR NOT NULL,
    Country      VARCHAR NOT NULL,
    ContactEmail VARCHAR
);

CREATE TABLE Branch (
    BranchID   INTEGER PRIMARY KEY,
    BranchName VARCHAR NOT NULL,
    City       VARCHAR NOT NULL,
    OpenedDate DATE
);

CREATE TABLE Employee (
    EmployeeID INTEGER PRIMARY KEY,
    BranchID   INTEGER NOT NULL REFERENCES Branch(BranchID),
    FullName   VARCHAR NOT NULL,
    JobRole    VARCHAR NOT NULL,
    HiredDate  DATE
);

CREATE TABLE Customer (
    CustomerID   INTEGER PRIMARY KEY,
    CustomerName VARCHAR NOT NULL,
    City         VARCHAR,
    JoinedDate   DATE
);

CREATE TABLE Product (
    ProductID   INTEGER PRIMARY KEY,
    SKU         VARCHAR NOT NULL UNIQUE,
    ProductName VARCHAR NOT NULL,
    Category    VARCHAR NOT NULL,
    SupplierID  INTEGER NOT NULL REFERENCES Supplier(SupplierID),
    UnitCost    DECIMAL(10,2) NOT NULL CHECK (UnitCost  >= 0),
    UnitPrice   DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0)
);

CREATE TABLE Inventory (
    ProductID      INTEGER NOT NULL REFERENCES Product(ProductID),
    BranchID       INTEGER NOT NULL REFERENCES Branch(BranchID),
    QuantityOnHand INTEGER NOT NULL DEFAULT 0 CHECK (QuantityOnHand >= 0),
    ReorderPoint   INTEGER NOT NULL DEFAULT 0,
    LastCounted    DATE,
    PRIMARY KEY (ProductID, BranchID)
);

CREATE TABLE "Order" (
    OrderID      INTEGER PRIMARY KEY,
    OrderType    VARCHAR NOT NULL CHECK (OrderType IN ('SALES','PURCHASE')),
    BranchID     INTEGER NOT NULL REFERENCES Branch(BranchID),
    EmployeeID   INTEGER          REFERENCES Employee(EmployeeID),
    CustomerID   INTEGER          REFERENCES Customer(CustomerID),
    SupplierID   INTEGER          REFERENCES Supplier(SupplierID),
    OrderDate    DATE NOT NULL,
    PromisedDate DATE,
    ReceivedDate DATE
);

CREATE TABLE OrderDetails (
    OrderID   INTEGER NOT NULL REFERENCES "Order"(OrderID),
    LineNo    INTEGER NOT NULL,
    ProductID INTEGER NOT NULL REFERENCES Product(ProductID),
    Quantity  INTEGER NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (OrderID, LineNo)
);

CREATE TABLE StockCount (
    CountID    INTEGER PRIMARY KEY,
    ProductID  INTEGER NOT NULL REFERENCES Product(ProductID),
    BranchID   INTEGER NOT NULL REFERENCES Branch(BranchID),
    CountDate  DATE NOT NULL,
    CountedQty INTEGER NOT NULL CHECK (CountedQty >= 0),
    CountedBy  INTEGER REFERENCES Employee(EmployeeID)
);

CREATE TABLE InventoryMovement (
    MovementID   INTEGER PRIMARY KEY,
    ProductID    INTEGER NOT NULL REFERENCES Product(ProductID),
    BranchID     INTEGER NOT NULL REFERENCES Branch(BranchID),
    EmployeeID   INTEGER          REFERENCES Employee(EmployeeID),
    MovementType VARCHAR NOT NULL CHECK (MovementType IN
                 ('RECEIPT','SALE','TRANSFER_IN','TRANSFER_OUT',
                  'ADJUSTMENT','WASTE','RETURN')),
    Quantity     INTEGER NOT NULL,
    MovementDate DATE NOT NULL,
    SourceRef    VARCHAR
);
