/*
    M10 common setup — search corpus for AdventureGearAI.

    Seeds search.SearchDocuments from the canonical AdventureGearAI content
    (customer.ProductReviews joined to catalog.Products), expanding the base
    reviews into >= 100 documents so DiskANN meets its minimum vector count. Each
    row carries a non-null SearchVector so exact and approximate vector search
    have data to run against. The search schema is created by the core bootstrap;
    this script is idempotent (it recreates the corpus on each run).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'search.SearchDocuments'))
    DROP FULLTEXT INDEX ON search.SearchDocuments;
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'AdventureGearSearchCatalog')
    DROP FULLTEXT CATALOG AdventureGearSearchCatalog;
DROP TABLE IF EXISTS search.SearchDocuments;
GO

CREATE TABLE search.SearchDocuments
(
    DocumentID int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_SearchDocuments PRIMARY KEY,
    ProductID int NOT NULL
        CONSTRAINT FK_SearchDocuments_Products REFERENCES catalog.Products(ProductID),
    ProductName nvarchar(120) NOT NULL,
    DocumentText nvarchar(max) NOT NULL,
    Rating tinyint NOT NULL,
    SearchVector vector(3) NOT NULL
);
GO

INSERT search.SearchDocuments (ProductID, ProductName, DocumentText, Rating, SearchVector)
SELECT
    p.ProductID,
    p.ProductName,
    CONCAT(r.ReviewTitle, N'. ', r.ReviewText, N' Training scenario ', variants.VariantNumber, N'.'),
    r.Rating,
    CASE
        WHEN p.ProductName LIKE N'%Tire%' THEN CAST('[1,0,0]' AS vector(3))
        WHEN p.ProductName LIKE N'%Light%' THEN CAST('[0,1,0]' AS vector(3))
        ELSE CAST('[0,0,1]' AS vector(3))
    END
FROM customer.ProductReviews AS r
INNER JOIN catalog.Products AS p ON p.ProductID = r.ProductID
CROSS JOIN
(
    VALUES
        (1), (2), (3), (4), (5),
        (6), (7), (8), (9), (10)
) AS variants(VariantNumber);
GO

PRINT N'M10 search.SearchDocuments seeded with >= 100 vectorized AdventureGearAI documents.';
GO
