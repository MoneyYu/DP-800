SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS dbo.EmbeddingDocuments;

CREATE TABLE dbo.EmbeddingDocuments
(
    DocumentID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmbeddingDocuments PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    DocumentText nvarchar(max) NOT NULL,
    ContentHash varbinary(32) NOT NULL
);

INSERT dbo.EmbeddingDocuments (ProductName, DocumentText, ContentHash)
SELECT
    p.ProductName,
    CONCAT(p.ProductName, N' - ', r.ReviewTitle, N': ', r.ReviewText),
    HASHBYTES('SHA2_256', CONCAT(p.ProductName, N' - ', r.ReviewTitle, N': ', r.ReviewText))
FROM dbo.ProductReviews AS r
INNER JOIN dbo.Products AS p ON p.ProductID = r.ProductID;
GO
