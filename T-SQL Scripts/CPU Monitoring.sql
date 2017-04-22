--=========================================--
/*** SQL SERVER CPU MONITORING QUERIES ***/
--=========================================------
-- Supported Versions SQL server 2008 and higher
-------------------------------------------------

-------------------------------------
/*** 1. Current CPU Utilization ***/
-------------------------------------

DECLARE @ts BIGINT; 
DECLARE @lastNmin TINYINT; 

SELECT @ts = (SELECT cpu_ticks / ( cpu_ticks / ms_ticks ) 
              FROM   sys.dm_os_sys_info); 

SELECT TOP(1) Dateadd(ms, -1 * ( @ts - [timestamp] ), Getdate())AS [EventTime], 
              sqlprocessutilization                             AS 
              [SQL Server Utilization], 
              100 - systemidle - sqlprocessutilization          AS 
              [Other Process CPU_Utilization], 
              systemidle                                        AS [System Idle] 
FROM   (SELECT 
record.value('(./Record/@id)[1]', 'int')                                                  AS record_id, 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')        AS [SystemIdle], 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')AS [SQLProcessUtilization], 
[timestamp] 
 FROM   (SELECT[timestamp], 
               CONVERT(XML, record) AS [record] 
         FROM   sys.dm_os_ring_buffers 
         WHERE  ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
                AND record LIKE'%%')AS x)AS y 
ORDER  BY record_id DESC; 


---------------------------------------------
/*** 2.CPU Utilization for last N minutes***/
---------------------------------------------
-- Mention the minutes in @lastNmin Parameter

DECLARE @ts BIGINT; 
DECLARE @lastNmin TINYINT; 

SET @lastNmin = 15; --Mention the Minutes Here 

SELECT @ts = (SELECT cpu_ticks / ( cpu_ticks / ms_ticks ) 
              FROM   sys.dm_os_sys_info); 

SELECT TOP(@lastNmin) Dateadd(ms, -1 * ( @ts - [timestamp] ), Getdate())AS 
                      [EventTime], 
                      sqlprocessutilization                             AS 
                      [SQL Server Utilization], 
                      100 - systemidle - sqlprocessutilization          AS 
                      [Other Process CPU_Utilization], 
                      systemidle                                        AS 
                      [System Idle] 
FROM   (SELECT 
record.value('(./Record/@id)[1]', 'int')                                                  AS record_id, 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')        AS [SystemIdle], 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')AS [SQLProcessUtilization], 
[timestamp] 
 FROM   (SELECT[timestamp], 
               CONVERT(XML, record) AS [record] 
         FROM   sys.dm_os_ring_buffers 
         WHERE  ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
                AND record LIKE'%%')AS x)AS y 
ORDER  BY record_id DESC; 


------------------------------------------
/*** 3.Database wise CPU Utilization ***/
------------------------------------------

WITH db_cpu 
     AS (SELECT databaseid, 
                Db_name(databaseid)   AS [DatabaseName], 
                Sum(total_worker_time)AS [CPU_Time(Ms)] 
         FROM   sys.dm_exec_query_stats AS qs 
                CROSS apply(SELECT CONVERT(INT, value)AS [DatabaseID] 
                            FROM   sys.Dm_exec_plan_attributes(qs.plan_handle) 
                            WHERE  attribute = N'dbid')AS epa 
         GROUP  BY databaseid) 
SELECT Row_number() 
         OVER( 
           ORDER BY [cpu_time(ms)] DESC)                             AS [SNO], 
       databasename                                                  AS [DBName] 
       , 
       [cpu_time(ms)], 
       Cast([cpu_time(ms)] * 1.0 / Sum([cpu_time(ms)]) 
                                     OVER() * 100.0 AS DECIMAL(5, 2))AS 
       [CPUPercent] 
FROM   db_cpu 
WHERE  databaseid > 4 -- system databases  
       AND databaseid <> 32767 -- ResourceDB  
ORDER  BY sno 
OPTION(recompile); 


---------------------------------------
/*** 4.Query Wise CPU Utilization ***/
---------------------------------------
-- This Query will show the queries and its CPU time if the avg CPU usgae is > 50
-- You can modify this in IF @AvgCPUUtilization >= 50

SET nocount ON 

DECLARE @ts_now BIGINT 
DECLARE @AvgCPUUtilization DECIMAL(10, 2) 

SELECT @ts_now = cpu_ticks / ( cpu_ticks / ms_ticks ) 
FROM   sys.dm_os_sys_info 

-- load the CPU utilization in the past 10 minutes into the temp table, you can load them into a permanent table
SELECT TOP(10) sqlprocessutilization                                  AS 
               [SQLServerProcessCPUUtilization], 
               systemidle                                             AS 
               [SystemIdleProcess], 
               100 - systemidle - sqlprocessutilization               AS 
               [OtherProcessCPU Utilization], 
               Dateadd(ms, -1 * ( @ts_now - [timestamp] ), Getdate()) AS 
               [EventTime] 
INTO   #cpuutilization 
FROM   (SELECT record.value('(./Record/@id)[1]', 'int') 
                      AS record_id, 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 
'int') 
               AS [SystemIdle], 
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS [SQLProcessUtilization], 
[timestamp] 
 FROM   (SELECT [timestamp], 
                CONVERT(XML, record) AS [record] 
         FROM   sys.dm_os_ring_buffers 
         WHERE  ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' 
                AND record LIKE '%<SystemHealth>%') AS x) AS y 
ORDER  BY record_id DESC 

-- check if the average CPU utilization was over 50% in the past 10 minutes 

SELECT @AvgCPUUtilization = Avg([sqlserverprocesscpuutilization] 
                                + [otherprocesscpu utilization]) 
FROM   #cpuutilization 
WHERE  eventtime > Dateadd(mm, -10, Getdate()) 

IF @AvgCPUUtilization >= 50 
  BEGIN 
      SELECT TOP(10) CONVERT(VARCHAR(25), @AvgCPUUtilization) 
                     + '%'                                         AS 
                     [AvgCPUUtilization], 
                     Getdate() 
                     [Date and Time] 
                     , 
                     r.cpu_time, 
                     r.total_elapsed_time, 
                     s.session_id, 
                     s.login_name, 
                     s.host_name, 
                     Db_name(r.database_id)                        AS 
                     DatabaseName 
                     , 
      Substring (t.text, ( r.statement_start_offset / 2 ) + 1, ( 
      ( CASE 
          WHEN r.statement_end_offset = -1 THEN 
          Len(CONVERT(NVARCHAR(max), t.text)) * 
          2 
          ELSE r.statement_end_offset 
        END - r.statement_start_offset ) / 2 ) + 1) AS 
      [IndividualQuery], 
      Substring(text, 1, 200)                       AS [ParentQuery], 
      r.status, 
      r.start_time, 
      r.wait_type, 
      s.program_name 
      INTO   #possiblecpuutilizationqueries 
      FROM   sys.dm_exec_sessions s 
             INNER JOIN sys.dm_exec_connections c 
                     ON s.session_id = c.session_id 
             INNER JOIN sys.dm_exec_requests r 
                     ON c.connection_id = r.connection_id 
             CROSS apply sys.Dm_exec_sql_text(r.sql_handle) t 
      WHERE  s.session_id > 50 
             AND r.session_id != @@spid 
      ORDER  BY r.cpu_time DESC 

      
      SELECT * 
      FROM   #possiblecpuutilizationqueries 
  END 

-- drop the temp tables 
IF Object_id('TEMPDB..#CPUUtilization') IS NOT NULL 
  DROP TABLE #cpuutilization 

IF Object_id('TEMPDB..#PossibleCPUUtilizationQueries') IS NOT NULL 
  DROP TABLE #possiblecpuutilizationqueries 


---------------------------------
/*** 5.TOP costliest Queries ***/
---------------------------------
-- This will give top 20 costliest queries which are executed recently. 

SELECT TOP (20) st.text              AS Query, 
                qs.execution_count, 
                qs.total_worker_time AS Total_CPU, 
                total_CPU_inSeconds = --Converted from microseconds 
                qs.total_worker_time / 1000000, 
                average_CPU_inSeconds = --Converted from microseconds 
                ( qs.total_worker_time / 1000000 ) / qs.execution_count, 
                qs.total_elapsed_time, 
                total_elapsed_time_inSeconds = --Converted from microseconds 
                qs.total_elapsed_time / 1000000, 
                qp.query_plan 
FROM   sys.dm_exec_query_stats AS qs 
       CROSS apply sys.Dm_exec_sql_text(qs.sql_handle) AS st 
       CROSS apply sys.Dm_exec_query_plan (qs.plan_handle) AS qp 
ORDER  BY qs.total_worker_time DESC 
OPTION (recompile); 


-------------------------------------------------------------
/*** 5.TOP costliest Queries with batch and more details ***/
-------------------------------------------------------------

SELECT TOP 50
  [Avg. MultiCore/CPU time(sec)] = qs.total_worker_time / 1000000 / qs.execution_count,
  [Total MultiCore/CPU time(sec)] = qs.total_worker_time / 1000000,
  [Avg. Elapsed Time(sec)] = qs.total_elapsed_time / 1000000 / qs.execution_count,
  [Total Elapsed Time(sec)] = qs.total_elapsed_time / 1000000,
  qs.execution_count,
  [Avg. I/O] = (total_logical_reads + total_logical_writes) / qs.execution_count,
  [Total I/O] = total_logical_reads + total_logical_writes,
  Query = SUBSTRING(qt.[text], (qs.statement_start_offset / 2) + 1,
  (
  (
  CASE qs.statement_end_offset
    WHEN -1 THEN DATALENGTH(qt.[text])
    ELSE qs.statement_end_offset
  END - qs.statement_start_offset
  ) / 2
  ) + 1
  ),
  Batch = qt.[text],
  [DB] = DB_NAME(qt.[dbid]),
  qs.last_execution_time,
  qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.[sql_handle]) AS qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp

ORDER BY [Total MultiCore/CPU time(sec)] DESC;
