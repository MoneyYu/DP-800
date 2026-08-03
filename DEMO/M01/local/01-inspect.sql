SELECT ProductID, CurrentPrice, ValidFrom, ValidTo
FROM dbo.ProductPrice FOR SYSTEM_TIME ALL
ORDER BY ProductID, ValidFrom;

SELECT ProductName, JSON_VALUE(ProductMetadata, '$.terrain') AS Terrain
FROM dbo.Products
WHERE ProductMetadata IS NOT NULL;

SELECT $PARTITION.PF_DP800_OrderDate(OrderDate) AS PartitionNumber, COUNT(*) AS Orders
FROM dbo.PartitionedOrders
GROUP BY $PARTITION.PF_DP800_OrderDate(OrderDate)
ORDER BY PartitionNumber;

SELECT sourceNode.ProductName, edge.RelationshipType, targetNode.ProductName AS RelatedProduct
FROM dbo.ProductNode AS sourceNode,
     dbo.ProductRelatedTo AS edge,
     dbo.ProductNode AS targetNode
WHERE MATCH(sourceNode-(edge)->targetNode);
GO
