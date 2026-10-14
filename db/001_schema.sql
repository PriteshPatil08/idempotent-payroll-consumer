-- Idempotent Payroll Consumer: schema
-- Invariant: for every MessageId, the Payroll change, the ProcessedMessage row and the
-- Outbox event either all exist or none exist (enforced by one transaction in the consumer).

-- Required for filtered indexes; legacy sqlcmd defaults QUOTED_IDENTIFIER to OFF.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_ID('IdempotentPayroll') IS NULL
    CREATE DATABASE IdempotentPayroll;
GO
USE IdempotentPayroll;
GO

DROP TABLE IF EXISTS dbo.Outbox;
DROP TABLE IF EXISTS dbo.ProcessedMessage;
DROP TABLE IF EXISTS dbo.Payroll;
GO

-- Business state
CREATE TABLE dbo.Payroll
(
    PayrollId    BIGINT         NOT NULL CONSTRAINT PK_Payroll PRIMARY KEY,
    Status       VARCHAR(20)    NOT NULL CONSTRAINT DF_Payroll_Status DEFAULT ('Pending'),
    Amount       DECIMAL(19, 4) NOT NULL,
    ProcessedAt  DATETIME2(3)   NULL,
    CONSTRAINT CK_Payroll_Status CHECK (Status IN ('Pending', 'Processed'))
);

-- Inbox / dedup ledger. The PRIMARY KEY is the unique constraint that makes
-- concurrent duplicates impossible, regardless of any application-level check.
CREATE TABLE dbo.ProcessedMessage
(
    MessageId    VARCHAR(100)   NOT NULL CONSTRAINT PK_ProcessedMessage PRIMARY KEY,
    ProcessedAt  DATETIME2(3)   NOT NULL CONSTRAINT DF_ProcessedMessage_ProcessedAt DEFAULT (SYSUTCDATETIME())
);

-- Transactional outbox. Written in the same transaction as the business change;
-- a separate relay publishes unpublished rows to Kafka.
CREATE TABLE dbo.Outbox
(
    Sequence     BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Outbox PRIMARY KEY,
    EventId      UNIQUEIDENTIFIER NOT NULL CONSTRAINT UQ_Outbox_EventId UNIQUE,
    EventType    VARCHAR(100)   NOT NULL,
    AggregateId  VARCHAR(100)   NOT NULL,
    Payload      NVARCHAR(MAX)  NOT NULL,
    OccurredAt   DATETIME2(3)   NOT NULL CONSTRAINT DF_Outbox_OccurredAt DEFAULT (SYSUTCDATETIME()),
    PublishedAt  DATETIME2(3)   NULL
);

-- The relay only ever asks "what hasn't been published yet, in order?"
CREATE INDEX IX_Outbox_Unpublished ON dbo.Outbox (Sequence) WHERE PublishedAt IS NULL;
GO

-- Seed data
INSERT dbo.Payroll (PayrollId, Amount) VALUES (987, 250000.00);
GO
