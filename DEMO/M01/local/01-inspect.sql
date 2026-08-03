/*
    M01 local/01-inspect.sql

    Read-only inspection of the Module 1 objects against AdventureGearAI. Safe to
    re-run: it performs no writes.
*/
SET NOCOUNT ON;
GO

/* Temporal history: current + historical price versions for each product. */
SELECT ProductID, CurrentPrice, ValidFrom, ValidTo
FROM catalog.ProductPrice FOR SYSTEM_TIME ALL
ORDER BY ProductID, ValidFrom;

/* JSON projection from the canonical ProductMetadata document. */
SELECT ProductName,
       JSON_VALUE(ProductMetadata, '$.terrain') AS Terrain,
       MetadataFrame
FROM catalog.Products
WHERE ProductMetadata IS NOT NULL
ORDER BY ProductID;

/* Partition distribution of the range-partitioned teaching object. */
SELECT $PARTITION.PF_AdventureGear_OrderDate(OrderDate) AS PartitionNumber, COUNT(*) AS Orders
FROM sales.PartitionedOrders
GROUP BY $PARTITION.PF_AdventureGear_OrderDate(OrderDate)
ORDER BY PartitionNumber;

/* Product graph: which products complement which. */
SELECT sourceNode.ProductName, edge.RelationshipType, targetNode.ProductName AS RelatedProduct
FROM catalog.ProductNode AS sourceNode,
     catalog.ProductRelatedTo AS edge,
     catalog.ProductNode AS targetNode
WHERE MATCH(sourceNode-(edge)->targetNode)
ORDER BY targetNode.ProductName;
GO
