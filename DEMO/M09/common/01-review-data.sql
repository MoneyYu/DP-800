/*
    M09 common setup — embedding source documents for AdventureGearAI.

    Builds ai.EmbeddingDocuments from the canonical AdventureGearAI content:
    customer.ProductReviews joined to catalog.Products. Each row is the natural
    text an embedding model would encode. The ai schema is created by the core
    bootstrap; this script is idempotent (it recreates the table on each run).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

DROP TABLE IF EXISTS ai.EmbeddingDocuments;
GO

CREATE TABLE ai.EmbeddingDocuments
(
    DocumentID int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_EmbeddingDocuments PRIMARY KEY,
    ProductID int NOT NULL
        CONSTRAINT FK_EmbeddingDocuments_Products REFERENCES catalog.Products(ProductID),
    ProductName nvarchar(120) NOT NULL,
    DocumentText nvarchar(max) NOT NULL,
    ContentHash varbinary(32) NOT NULL
);
GO

INSERT ai.EmbeddingDocuments (ProductID, ProductName, DocumentText, ContentHash)
SELECT
    p.ProductID,
    p.ProductName,
    CONCAT(p.ProductName, N' - ', r.ReviewTitle, N': ', r.ReviewText),
    HASHBYTES('SHA2_256', CONCAT(p.ProductName, N' - ', r.ReviewTitle, N': ', r.ReviewText))
FROM customer.ProductReviews AS r
INNER JOIN catalog.Products AS p ON p.ProductID = r.ProductID;
GO

PRINT N'M09 ai.EmbeddingDocuments seeded from AdventureGearAI products and reviews.';
GO
