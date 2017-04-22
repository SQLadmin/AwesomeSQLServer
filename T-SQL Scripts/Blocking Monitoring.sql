/********************************************************************************************

***  Blocking and deadlock monitor ***
------------------------------------------------

I have prepared this script to monitor blocking  sessions with sp_whoisactive,
So first you need tocreate sp_whoisactive stored procedure, 
please downad it from the link,

https://github.com/SqlAdmin/AwesomeSQLServer/blob/master/T-SQL%20Scripts/sp_whoisactive.sql

*******************************************************************************************/ 


-- To get overall info about current sessions

EXEC sp_whoisactive
---------------------------------------
/*** 1. Monitor blocking session ***/
---------------------------------------

EXEC sp_WhoIsActive @find_block_leaders = 1,
                    @output_column_list = '[dd%][session_id][database_name][login_name] [sql_text][wait_info][blocking_session_id][blocked_session_count]',
                    @sort_order = '[start_time] ASC';


---------------------------------------
/*** 2. Monitor deadlocking session ***/
---------------------------------------

WITH [Blocking]
AS (SELECT
  w.[session_id],
  s.[original_login_name],
  s.[login_name],
  w.[wait_duration_ms],
  w.[wait_type],
  r.[status],
  r.[wait_resource],
  w.[resource_description],
  s.[program_name],
  w.[blocking_session_id],
  s.[host_name],
  r.[command],
  r.[percent_complete],
  r.[cpu_time],
  r.[total_elapsed_time],
  r.[reads],
  r.[writes],
  r.[logical_reads],
  r.[row_count],
  q.[text],
  q.[dbid],
  p.[query_plan],
  r.[plan_handle]
FROM [sys].[dm_os_waiting_tasks] w
INNER JOIN [sys].[dm_exec_sessions] s
  ON w.[session_id] = s.[session_id]
INNER JOIN [sys].[dm_exec_requests] r
  ON s.[session_id] = r.[session_id]
CROSS APPLY [sys].[dm_exec_sql_text](r.[plan_handle]) q
CROSS APPLY [sys].[dm_exec_query_plan](r.[plan_handle]) p
WHERE w.[session_id] > 50
AND w.[wait_type] NOT IN ('DBMIRROR_DBM_EVENT'
, 'ASYNC_NETWORK_IO'))
SELECT
  b.[session_id] AS [WaitingSessionID],
  b.[blocking_session_id] AS [BlockingSessionID],
  b.[login_name] AS [WaitingUserSessionLogin],
  s1.[login_name] AS [BlockingUserSessionLogin],
  b.[original_login_name] AS [WaitingUserConnectionLogin],
  s1.[original_login_name] AS [BlockingSessionConnectionLogin],
  b.[wait_duration_ms] AS [WaitDuration],
  b.[wait_type] AS [WaitType],
  t.[request_mode] AS [WaitRequestMode],
  UPPER(b.[status]) AS [WaitingProcessStatus],
  UPPER(s1.[status]) AS [BlockingSessionStatus],
  b.[wait_resource] AS [WaitResource],
  t.[resource_type] AS [WaitResourceType],
  t.[resource_database_id] AS [WaitResourceDatabaseID],
  DB_NAME(t.[resource_database_id]) AS [WaitResourceDatabaseName],
  b.[resource_description] AS [WaitResourceDescription],
  b.[program_name] AS [WaitingSessionProgramName],
  s1.[program_name] AS [BlockingSessionProgramName],
  b.[host_name] AS [WaitingHost],
  s1.[host_name] AS [BlockingHost],
  b.[command] AS [WaitingCommandType],
  b.[text] AS [WaitingCommandText],
  b.[row_count] AS [WaitingCommandRowCount],
  b.[percent_complete] AS [WaitingCommandPercentComplete],
  b.[cpu_time] AS [WaitingCommandCPUTime],
  b.[total_elapsed_time] AS [WaitingCommandTotalElapsedTime],
  b.[reads] AS [WaitingCommandReads],
  b.[writes] AS [WaitingCommandWrites],
  b.[logical_reads] AS [WaitingCommandLogicalReads],
  b.[query_plan] AS [WaitingCommandQueryPlan],
  b.[plan_handle] AS [WaitingCommandPlanHandle]
FROM [Blocking] b
INNER JOIN [sys].[dm_exec_sessions] s1
  ON b.[blocking_session_id] = s1.[session_id]
INNER JOIN [sys].[dm_tran_locks] t
  ON t.[request_session_id] = b.[session_id]
WHERE t.[request_status] = 'WAIT'
GO     