SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'dbo.SearchDocuments'))
    DROP FULLTEXT INDEX ON dbo.SearchDocuments;
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'DP800_SearchCatalog')
    DROP FULLTEXT CATALOG DP800_SearchCatalog;
DROP TABLE IF EXISTS dbo.SearchDocuments;

CREATE TABLE dbo.SearchDocuments
(
    DocumentID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_SearchDocuments PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    DocumentText nvarchar(max) NOT NULL,
    Rating tinyint NOT NULL
);

INSERT dbo.SearchDocuments (ProductName, DocumentText, Rating)
SELECT
    p.ProductName,
    CONCAT(r.ReviewTitle, N'. ', r.ReviewText, N' Training scenario ', variants.VariantNumber, N'.'),
    r.Rating
FROM dbo.ProductReviews AS r
INNER JOIN dbo.Products AS p ON p.ProductID = r.ProductID
CROSS JOIN
(
    VALUES
        (1), (2), (3), (4), (5),
        (6), (7), (8), (9), (10),
        (11), (12), (13), (14), (15),
        (16), (17), (18), (19), (20)
) AS variants(VariantNumber);
GO
