SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
CREATE TABLE dbo.WhatsGoingOnHistory(
 [Runtime] [DateTime],
 [session_id] [smallint] NOT NULL,
 [login_name] [varchar](128) NOT NULL,
 [host_name] [varchar](128) NULL,
 [DBName] [varchar](128) NULL,
 [Individual Query] [varchar](max) NULL,
 [Parent Query] [varchar](200) NULL,
 [status] [varchar](30) NULL,
 [start_time] [datetime] NULL,
 [wait_type] [varchar](60) NULL,
 [program_name] [varchar](128) NULL
)
GO
CREATE UNIQUE NONCLUSTERED INDEX
[NONCLST_WhatsGoingOnHistory] ON [dbo].[WhatsGoingOnHistory]
([Runtime] ASC, [session_id] ASC)
GO
INSERT INTO dbo.WhatsGoingOnHistory
SELECT
 GETDATE()
 , s.session_id
 , s.login_name
 , s.host_name
 , DB_NAME(r.database_id) AS DBName
 , SUBSTRING (t.text,(r.statement_start_offset/2) + 1,
 ((CASE WHEN r.statement_end_offset = -1
 THEN LEN(CONVERT(NVARCHAR(MAX), t.text)) * 2
 ELSE r.statement_end_offset
 END - r.statement_start_offset)/2) + 1) AS [Individual Query]
 , SUBSTRING(text, 1, 200) AS [Parent Query]
 , r.status
 , r.start_time
 , r.wait_type
 , s.program_name
FROM sys.dm_exec_sessions s
INNER JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
INNER JOIN sys.dm_exec_requests r ON c.connection_id = r.connection_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.session_id > 50
 AND r.session_id != @@spid
WAITFOR DELAY '00:01:00'
GO 1440 -- 60 * 24 (one day)
