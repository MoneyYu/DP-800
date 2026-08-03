DECLARE @Question nvarchar(1000) = N'Which tire resists punctures on rough roads?';
EXEC ai.usp_BuildRagPrompt @Question = @Question;
GO
