/*
    M09 common setup — embedding source documents for AdventureGearAI.

    Builds ai.EmbeddingDocuments and ai.EmbeddingChunks from the canonical
    AdventureGearAI content: customer.ProductReviews joined to catalog.Products.
    The ai schema is created by the core bootstrap; this script is idempotent
    (it recreates its source-document and chunk tables on each run).
    M09 共用設定：AdventureGearAI 的嵌入來源文件與區塊。
    從標準 AdventureGearAI 內容建立 ai.EmbeddingDocuments 與 ai.EmbeddingChunks：
    customer.ProductReviews 與 catalog.Products 的聯結。ai 結構描述由核心 bootstrap
    建立；此指令碼具冪等性（每次執行會重新建立來源文件與區塊資料表）。
    */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE [AdventureGearAI];
GO

DROP TABLE IF EXISTS ai.EmbeddingChunks;
DROP TABLE IF EXISTS ai.EmbeddingDocuments;
GO

CREATE TABLE ai.EmbeddingDocuments
(
    DocumentID int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_EmbeddingDocuments PRIMARY KEY,
    ProductID int NOT NULL
        CONSTRAINT FK_EmbeddingDocuments_Products REFERENCES catalog.Products(ProductID),
    ReviewID int NOT NULL
        CONSTRAINT FK_EmbeddingDocuments_ProductReviews REFERENCES customer.ProductReviews(ReviewID),
    ProductName nvarchar(120) NOT NULL,
    DocumentText nvarchar(max) NOT NULL,
    ContentHash varbinary(32) NOT NULL
);
GO

CREATE TABLE ai.EmbeddingChunks
(
    EmbeddingChunkID bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_EmbeddingChunks PRIMARY KEY,
    DocumentID int NOT NULL
        CONSTRAINT FK_EmbeddingChunks_Documents REFERENCES ai.EmbeddingDocuments(DocumentID),
    ProductID int NOT NULL
        CONSTRAINT FK_EmbeddingChunks_Products REFERENCES catalog.Products(ProductID),
    ReviewID int NOT NULL
        CONSTRAINT FK_EmbeddingChunks_ProductReviews REFERENCES customer.ProductReviews(ReviewID),
    ChunkText nvarchar(max) NOT NULL,
    ChunkOrder bigint NOT NULL,
    ChunkOffset bigint NOT NULL,
    ChunkLength int NOT NULL,
    ChunkSetID bigint NOT NULL
);
GO

INSERT ai.EmbeddingDocuments (ProductID, ReviewID, ProductName, DocumentText, ContentHash)
SELECT
    p.ProductID,
    r.ReviewID,
    p.ProductName,
    CONCAT(p.ProductName, N' - ', r.ReviewTitle, N': ', r.ReviewText),
    HASHBYTES('SHA2_256', CONCAT(p.ProductName, N' - ', r.ReviewTitle, N': ', r.ReviewText))
FROM customer.ProductReviews AS r
INNER JOIN catalog.Products AS p ON p.ProductID = r.ProductID;
GO

DECLARE @compatibilityLevel int =
(
    SELECT compatibility_level
    FROM sys.databases
    WHERE database_id = DB_ID()
);

IF @compatibilityLevel < 170
BEGIN
    PRINT N'M09 chunk generation skipped: AI_GENERATE_CHUNKS requires database compatibility level 170 or higher.';
END
ELSE
BEGIN
    EXEC sys.sp_executesql N'
        INSERT ai.EmbeddingChunks
        (
            DocumentID,
            ProductID,
            ReviewID,
            ChunkText,
            ChunkOrder,
            ChunkOffset,
            ChunkLength,
            ChunkSetID
        )
        SELECT
            d.DocumentID,
            d.ProductID,
            d.ReviewID,
            chunks.chunk,
            chunks.chunk_order,
            chunks.chunk_offset,
            chunks.chunk_length,
            chunks.chunk_set_id
        FROM ai.EmbeddingDocuments AS d
        CROSS APPLY AI_GENERATE_CHUNKS
        (
            SOURCE = d.DocumentText,
            CHUNK_TYPE = FIXED,
            CHUNK_SIZE = 160,
            OVERLAP = 10,
            ENABLE_CHUNK_SET_ID = 1
        ) AS chunks;';

    SELECT
        c.ProductID,
        c.ReviewID,
        c.ChunkSetID,
        c.ChunkOrder,
        c.ChunkOffset,
        c.ChunkLength,
        c.ChunkText
    FROM ai.EmbeddingChunks AS c
    ORDER BY c.ProductID, c.ReviewID, c.ChunkSetID, c.ChunkOrder;
END;
GO

PRINT N'M09 ai.EmbeddingDocuments seeded; ai.EmbeddingChunks generated when compatibility level supports AI_GENERATE_CHUNKS.';
GO
