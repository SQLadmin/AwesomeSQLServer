/*************************************************
I got this scripts from SQLskills.com 
writtern by Paul Randal.
*************************************************/

--==========================================--
/*** 1. Monitor IO on databases files from 
the server starting or Database Online ***/
--==========================================--

SELECT
  [ReadLatency] =
                 CASE
                   WHEN [num_of_reads] = 0 THEN 0
                   ELSE ([io_stall_read_ms] / [num_of_reads])
                 END,
  [WriteLatency] =
                  CASE
                    WHEN [num_of_writes] = 0 THEN 0
                    ELSE ([io_stall_write_ms] / [num_of_writes])
                  END,
  [Latency] =
             CASE
               WHEN ([num_of_reads] = 0 AND
                 [num_of_writes] = 0) THEN 0
               ELSE ([io_stall] / ([num_of_reads] + [num_of_writes]))
             END,
  [AvgBPerRead] =
                 CASE
                   WHEN [num_of_reads] = 0 THEN 0
                   ELSE ([num_of_bytes_read] / [num_of_reads])
                 END,
  [AvgBPerWrite] =
                  CASE
                    WHEN [num_of_writes] = 0 THEN 0
                    ELSE ([num_of_bytes_written] / [num_of_writes])
                  END,
  [AvgBPerTransfer] =
                     CASE
                       WHEN ([num_of_reads] = 0 AND
                         [num_of_writes] = 0) THEN 0
                       ELSE (([num_of_bytes_read] + [num_of_bytes_written]) /
                         ([num_of_reads] + [num_of_writes]))
                     END,
  LEFT([mf].[physical_name], 2) AS [Drive],
  DB_NAME([vfs].[database_id]) AS [DB],
  [mf].[physical_name]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS [vfs]
JOIN sys.master_files AS [mf]
  ON [vfs].[database_id] = [mf].[database_id]
  AND [vfs].[file_id] = [mf].[file_id]
-- WHERE [vfs].[file_id] = 2 -- log files
-- ORDER BY [Latency] DESC
-- ORDER BY [ReadLatency] DESC
ORDER BY [WriteLatency] DESC;
GO



--==========================================--
/*** 2. Monitor IO For particular period ***/
--==========================================--
-- In line 41 you can mention the time period
-- ie; WAITFOR DELAY '00:30:00';


IF EXISTS (SELECT
    *
  FROM [tempdb].[sys].[objects]
  WHERE [name] = N'##SQLskillsStats1')
  DROP TABLE [##SQLskillsStats1];

IF EXISTS (SELECT
    *
  FROM [tempdb].[sys].[objects]
  WHERE [name] = N'##SQLskillsStats2')
  DROP TABLE [##SQLskillsStats2];
GO

SELECT
  [database_id],
  [file_id],
  [num_of_reads],
  [io_stall_read_ms],
  [num_of_writes],
  [io_stall_write_ms],
  [io_stall],
  [num_of_bytes_read],
  [num_of_bytes_written],
  [file_handle] INTO ##SQLskillsStats1
FROM sys.dm_io_virtual_file_stats(NULL, NULL);
GO

WAITFOR DELAY '00:30:00';
GO

SELECT
  [database_id],
  [file_id],
  [num_of_reads],
  [io_stall_read_ms],
  [num_of_writes],
  [io_stall_write_ms],
  [io_stall],
  [num_of_bytes_read],
  [num_of_bytes_written],
  [file_handle] INTO ##SQLskillsStats2
FROM sys.dm_io_virtual_file_stats(NULL, NULL);
GO

WITH [DiffLatencies]
AS (SELECT
  -- Files that weren't in the first snapshot
  [ts2].[database_id],
  [ts2].[file_id],
  [ts2].[num_of_reads],
  [ts2].[io_stall_read_ms],
  [ts2].[num_of_writes],
  [ts2].[io_stall_write_ms],
  [ts2].[io_stall],
  [ts2].[num_of_bytes_read],
  [ts2].[num_of_bytes_written]
FROM [##SQLskillsStats2] AS [ts2]
LEFT OUTER JOIN [##SQLskillsStats1] AS [ts1]
  ON [ts2].[file_handle] = [ts1].[file_handle]
WHERE [ts1].[file_handle] IS NULL
UNION
SELECT
  -- Diff of latencies in both snapshots
  [ts2].[database_id],
  [ts2].[file_id],
  [ts2].[num_of_reads] - [ts1].[num_of_reads] AS [num_of_reads],
  [ts2].[io_stall_read_ms] - [ts1].[io_stall_read_ms] AS [io_stall_read_ms],
  [ts2].[num_of_writes] - [ts1].[num_of_writes] AS [num_of_writes],
  [ts2].[io_stall_write_ms] - [ts1].[io_stall_write_ms] AS [io_stall_write_ms],
  [ts2].[io_stall] - [ts1].[io_stall] AS [io_stall],
  [ts2].[num_of_bytes_read] - [ts1].[num_of_bytes_read] AS [num_of_bytes_read],
  [ts2].[num_of_bytes_written] - [ts1].[num_of_bytes_written] AS [num_of_bytes_written]
FROM [##SQLskillsStats2] AS [ts2]
LEFT OUTER JOIN [##SQLskillsStats1] AS [ts1]
  ON [ts2].[file_handle] = [ts1].[file_handle]
WHERE [ts1].[file_handle] IS NOT NULL)
SELECT
  DB_NAME([vfs].[database_id]) AS [DB],
  LEFT([mf].[physical_name], 2) AS [Drive],
  [mf].[type_desc],
  [num_of_reads] AS [Reads],
  [num_of_writes] AS [Writes],
  [ReadLatency(ms)] =
                     CASE
                       WHEN [num_of_reads] = 0 THEN 0
                       ELSE ([io_stall_read_ms] / [num_of_reads])
                     END,
  [WriteLatency(ms)] =
                      CASE
                        WHEN [num_of_writes] = 0 THEN 0
                        ELSE ([io_stall_write_ms] / [num_of_writes])
                      END,
  /*[Latency] =
      CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
          THEN 0 ELSE ([io_stall] / ([num_of_reads] + [num_of_writes])) END,*/
  [AvgBPerRead] =
                 CASE
                   WHEN [num_of_reads] = 0 THEN 0
                   ELSE ([num_of_bytes_read] / [num_of_reads])
                 END,
  [AvgBPerWrite] =
                  CASE
                    WHEN [num_of_writes] = 0 THEN 0
                    ELSE ([num_of_bytes_written] / [num_of_writes])
                  END,
  /*[AvgBPerTransfer] =
      CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
          THEN 0 ELSE
              (([num_of_bytes_read] + [num_of_bytes_written]) /
              ([num_of_reads] + [num_of_writes])) END,*/
  [mf].[physical_name]
FROM [DiffLatencies] AS [vfs]
JOIN sys.master_files AS [mf]
  ON [vfs].[database_id] = [mf].[database_id]
  AND [vfs].[file_id] = [mf].[file_id]
-- ORDER BY [ReadLatency(ms)] DESC
ORDER BY [WriteLatency(ms)] DESC;
GO

-- Cleanup
IF EXISTS (SELECT
    *
  FROM [tempdb].[sys].[objects]
  WHERE [name] = N'##SQLskillsStats1')
  DROP TABLE [##SQLskillsStats1];

IF EXISTS (SELECT
    *
  FROM [tempdb].[sys].[objects]
  WHERE [name] = N'##SQLskillsStats2')
  DROP TABLE [##SQLskillsStats2];
GO
