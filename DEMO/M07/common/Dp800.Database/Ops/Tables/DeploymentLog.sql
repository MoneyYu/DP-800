CREATE TABLE [ops].[DeploymentLog]
(
    [DeploymentID] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_DeploymentLog] PRIMARY KEY,
    [ReleaseTag] nvarchar(60) NOT NULL,
    [DeployedAtUtc] datetime2(3) NOT NULL CONSTRAINT [DF_DeploymentLog_DeployedAtUtc] DEFAULT SYSUTCDATETIME(),
    [DeployedBy] nvarchar(128) NOT NULL CONSTRAINT [DF_DeploymentLog_DeployedBy] DEFAULT SUSER_SNAME(),
    [Notes] nvarchar(400) NULL
);
