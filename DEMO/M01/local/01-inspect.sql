/*
    M01 local/01-inspect.sql

    Read-only inspection of the Module 1 objects against AdventureGearAI. Safe to
    re-run: it performs no writes.
    * 以唯讀方式檢查 AdventureGearAI 中的模組 1 物件；不會寫入資料，因此可安全重複執行。
*/
SET NOCOUNT ON;
GO

/* Temporal history: current + historical price versions for each product.
    * 檢查每項產品目前與歷程的時態價格版本。
*/
IF OBJECT_ID(N'catalog.ProductPrice', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        SELECT ProductID, CurrentPrice, ValidFrom, ValidTo
        FROM catalog.ProductPrice FOR SYSTEM_TIME ALL
        ORDER BY ProductID, ValidFrom;';
END;
ELSE
    PRINT N'M01 inspect skipped: catalog.ProductPrice is absent after an M01 scoped reset.';

/* JSON projection from the canonical ProductMetadata document.
    * 檢查標準 ProductMetadata 文件的 JSON 投影。
*/
IF COL_LENGTH(N'catalog.Products', N'MetadataFrame') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        SELECT ProductName,
               JSON_VALUE(ProductMetadata, ''$.terrain'') AS Terrain,
               MetadataFrame
        FROM catalog.Products
        WHERE ProductMetadata IS NOT NULL
        ORDER BY ProductID;';
END;
ELSE
    PRINT N'M01 inspect skipped: catalog.Products.MetadataFrame is absent after an M01 scoped reset.';

/* Partition distribution of the range-partitioned teaching object.
    * 檢查範圍分割教學物件的資料分布。
*/
IF OBJECT_ID(N'sales.PartitionedOrders', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        SELECT $PARTITION.PF_AdventureGear_OrderDate(OrderDate) AS PartitionNumber, COUNT(*) AS Orders
        FROM sales.PartitionedOrders
        GROUP BY $PARTITION.PF_AdventureGear_OrderDate(OrderDate)
        ORDER BY PartitionNumber;';
END;
ELSE
    PRINT N'M01 inspect skipped: sales.PartitionedOrders is absent after an M01 scoped reset.';

/* Product graph: which products complement which.
    * 檢查產品圖形中的互補關係。
*/
IF OBJECT_ID(N'catalog.ProductNode', N'U') IS NOT NULL
   AND OBJECT_ID(N'catalog.ProductRelatedTo', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        SELECT sourceNode.ProductName, edge.RelationshipType, targetNode.ProductName AS RelatedProduct
        FROM catalog.ProductNode AS sourceNode,
             catalog.ProductRelatedTo AS edge,
             catalog.ProductNode AS targetNode
        WHERE MATCH(sourceNode-(edge)->targetNode)
        ORDER BY targetNode.ProductName;';
END;
ELSE
    PRINT N'M01 inspect skipped: M01 graph teaching tables are absent after an M01 scoped reset.';
GO
