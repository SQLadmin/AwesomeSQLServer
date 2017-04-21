--=========================================--
/*** SQL SERVER MEMORY MONITORING QUERIES ***/
--=========================================--
-- Supported Versions SQL server 2008 and higher
-------------------------------------------------

----------------------------------
/*** 1. System Memory Status ***/
----------------------------------

SELECT total_physical_memory_kb / 1024                             AS 
       [Total Physical Memory], 
       available_physical_memory_kb / 1024                         AS 
       [Available Physical Memory], 
       total_page_file_kb / 1024                                   AS 
       [Total Page File (MB)], 
       available_page_file_kb / 1024                               AS 
       [Available Page File (MB)], 
       100 - ( 100 * Cast(available_physical_memory_kb AS DECIMAL(18, 3)) / Cast 
               ( 
                     total_physical_memory_kb AS DECIMAL(18, 3)) ) AS 
       'Percentage Used', 
       system_memory_state_desc                                    AS 
       [Memory State] 
FROM   sys.dm_os_sys_memory; 


---------------------------------------
/*** 2. SQL Server's memory Status ***/
---------------------------------------
-- this will show how much memory allocated to SQL Server , Buffer pool commit.

-- SQL server 2008 and earlier

SELECT
     (bpool_committed*8)/1024.0 as [Buffer Pool Committed (MB)],
     (bpool_commit_target*8)/1024.0 as [Buffer Pool Committed Targer (MB)]  
FROM sys.dm_os_sys_info;

-- SQL Server 2012 and later

SELECT
      (committed_kb)/1024.0 as [Buffer Pool Committed (MB)],
      (committed_target_kb)/1024.0 as [Buffer Pool Committed Targer (MB)] 
FROM  sys.dm_os_sys_info;


----------------------------------------------
/*** 3. Physical Memory Used By SQL Sever***/
----------------------------------------------
-- Find the actual Memory used by SQL Server

select
      convert(decimal (5,2),physical_memory_in_use_kb/1048576.0) AS 'Physical Memory Used By SQL (GB)',
      convert(decimal (5,2),locked_page_allocations_kb/1048576.0) As 'Locked Page Allocation',
       convert(decimal (5,2),available_commit_limit_kb/1048576.0) AS 'Available Commit Limit (GB)',
      page_fault_count as 'Page Fault Count'
from  sys.dm_os_process_memory;

------------------------------------------
/*** 4. Buffer Pool Usage By Databases ***/
------------------------------------------

DECLARE @total_buffer INT;
SELECT  @total_buffer = cntr_value 
FROM   sys.dm_os_performance_counters
WHERE  RTRIM([object_name]) LIKE '%Buffer Manager' 
       AND counter_name = 'Database Pages';
 
;WITH DBBuffer AS
(
SELECT  database_id,
        COUNT_BIG(*) AS db_buffer_pages,
        SUM (CAST ([free_space_in_bytes] AS BIGINT)) / (1024 * 1024) AS [MBEmpty]
FROM    sys.dm_os_buffer_descriptors
GROUP BY database_id
)
SELECT
       CASE [database_id] WHEN 32767 THEN 'Resource DB' ELSE DB_NAME([database_id]) END AS 'DataBase Name',
       db_buffer_pages AS 'DB Buffer Pages',
       db_buffer_pages / 128 AS 'DB Buffer Pages Used (MB)',
       [mbempty] AS 'DB Buffer Pages Free (MB)',
       CONVERT(DECIMAL(6,3), db_buffer_pages * 100.0 / @total_buffer) AS 'DB Buffer Percentage'
FROM   DBBuffer
ORDER BY [DB Buffer Pages Used (MB)] DESC;


--------------------------------------------
/*** 5. Memory Used By Database Objects ***/
--------------------------------------------

;WITH obj_buffer 
     AS (SELECT [Object] = o.NAME, 
                [Type] = o.type_desc, 
                [Index] = COALESCE(i.NAME, ''), 
                [Index_Type] = i.type_desc, 
                p.[object_id], 
                p.index_id, 
                au.allocation_unit_id 
         FROM   sys.partitions AS p 
                INNER JOIN sys.allocation_units AS au 
                        ON p.hobt_id = au.container_id 
                INNER JOIN sys.objects AS o 
                        ON p.[object_id] = o.[object_id] 
                INNER JOIN sys.indexes AS i 
                        ON o.[object_id] = i.[object_id] 
                           AND p.index_id = i.index_id 
         WHERE  au.[type] IN ( 1, 2, 3 ) 
                AND o.is_ms_shipped = 0) 
SELECT obj.[object], 
       obj.[type], 
       obj.[index], 
       obj.index_type, 
       Count_big(b.page_id)       AS 'Buffer Pages', 
       Count_big(b.page_id) / 128 AS 'Buffer MB' 
FROM   obj_buffer obj 
       INNER JOIN sys.dm_os_buffer_descriptors AS b 
               ON obj.allocation_unit_id = b.allocation_unit_id 
WHERE  b.database_id = Db_id() 
GROUP  BY obj.[object], 
          obj.[type], 
          obj.[index], 
          obj.index_type 
ORDER  BY [buffer pages] DESC; 


----------------------------------------
/*** 6. Costliest Stored Procedures ***/
----------------------------------------
-- Based on Logical reads

SELECT TOP(25) p.NAME                                      AS [SP Name], 
               qs.total_logical_reads                      AS 
               [TotalLogicalReads], 
               qs.total_logical_reads / qs.execution_count AS [AvgLogicalReads], 
               qs.execution_count                          AS 'execution_count', 
               qs.total_elapsed_time                       AS 
               'total_elapsed_time', 
               qs.total_elapsed_time / qs.execution_count  AS 'avg_elapsed_time' 
               , 
               qs.cached_time                              AS 
               'cached_time' 
FROM   sys.procedures AS p 
       INNER JOIN sys.dm_exec_procedure_stats AS qs 
               ON p.[object_id] = qs.[object_id] 
WHERE  qs.database_id = Db_id() 
ORDER  BY qs.total_logical_reads DESC; 


----------------------------------------------
/*** 7. Top Performance Counters – Memory ***/
----------------------------------------------

-- Get size of SQL Server Page in bytes 
DECLARE @pg_size      INT, 
        @Instancename VARCHAR(50) 

SELECT @pg_size = low 
FROM   master..spt_values 
WHERE  number = 1 
       AND type = 'E' 

-- Extract perfmon counters to a temporary table 
IF Object_id('tempdb..#perfmon_counters') IS NOT NULL 
  DROP TABLE #perfmon_counters 

SELECT * 
INTO   #perfmon_counters 
FROM   sys.dm_os_performance_counters; 

-- Get SQL Server instance name as it require for capturing Buffer Cache hit Ratio 
SELECT @Instancename = LEFT([object_name], ( Charindex(':', [object_name]) )) 
FROM   #perfmon_counters 
WHERE  counter_name = 'Buffer cache hit ratio'; 

SELECT * 
FROM   (SELECT 'Total Server Memory (GB)' AS Counter, 
               ( cntr_value / 1048576.0 ) AS Value 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Total Server Memory (KB)' 
        UNION ALL 
        SELECT 'Target Server Memory (GB)', 
               ( cntr_value / 1048576.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Target Server Memory (KB)' 
        UNION ALL 
        SELECT 'Connection Memory (MB)', 
               ( cntr_value / 1024.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Connection Memory (KB)' 
        UNION ALL 
        SELECT 'Lock Memory (MB)', 
               ( cntr_value / 1024.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Lock Memory (KB)' 
        UNION ALL 
        SELECT 'SQL Cache Memory (MB)', 
               ( cntr_value / 1024.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'SQL Cache Memory (KB)' 
        UNION ALL 
        SELECT 'Optimizer Memory (MB)', 
               ( cntr_value / 1024.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Optimizer Memory (KB) ' 
        UNION ALL 
        SELECT 'Granted Workspace Memory (MB)', 
               ( cntr_value / 1024.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Granted Workspace Memory (KB) ' 
        UNION ALL 
        SELECT 'Cursor memory usage (MB)', 
               ( cntr_value / 1024.0 ) 
        FROM   #perfmon_counters 
        WHERE  counter_name = 'Cursor memory usage' 
               AND instance_name = '_Total' 
        UNION ALL 
        SELECT 'Total pages Size (MB)', 
               ( cntr_value * @pg_size ) / 1048576.0 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Total pages' 
        UNION ALL 
        SELECT 'Database pages (MB)', 
               ( cntr_value * @pg_size ) / 1048576.0 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Database pages' 
        UNION ALL 
        SELECT 'Free pages (MB)', 
               ( cntr_value * @pg_size ) / 1048576.0 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Free pages' 
        UNION ALL 
        SELECT 'Reserved pages (MB)', 
               ( cntr_value * @pg_size ) / 1048576.0 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Reserved pages' 
        UNION ALL 
        SELECT 'Stolen pages (MB)', 
               ( cntr_value * @pg_size ) / 1048576.0 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Stolen pages' 
        UNION ALL 
        SELECT 'Cache Pages (MB)', 
               ( cntr_value * @pg_size ) / 1048576.0 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Plan Cache' 
               AND counter_name = 'Cache Pages' 
               AND instance_name = '_Total' 
        UNION ALL 
        SELECT 'Page Life Expectency in seconds', 
               cntr_value 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Page life expectancy' 
        UNION ALL 
        SELECT 'Free list stalls/sec', 
               cntr_value 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Free list stalls/sec' 
        UNION ALL 
        SELECT 'Checkpoint pages/sec', 
               cntr_value 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Checkpoint pages/sec' 
        UNION ALL 
        SELECT 'Lazy writes/sec', 
               cntr_value 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Buffer Manager' 
               AND counter_name = 'Lazy writes/sec' 
        UNION ALL 
        SELECT 'Memory Grants Pending', 
               cntr_value 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Memory Manager' 
               AND counter_name = 'Memory Grants Pending' 
        UNION ALL 
        SELECT 'Memory Grants Outstanding', 
               cntr_value 
        FROM   #perfmon_counters 
        WHERE  object_name = @Instancename + 'Memory Manager' 
               AND counter_name = 'Memory Grants Outstanding' 
        UNION ALL 
        SELECT 'process_physical_memory_low', 
               process_physical_memory_low 
        FROM   sys.dm_os_process_memory WITH (nolock) 
        UNION ALL 
        SELECT 'process_virtual_memory_low', 
               process_virtual_memory_low 
        FROM   sys.dm_os_process_memory WITH (nolock) 
        UNION ALL 
        SELECT 'Max_Server_Memory (MB)', 
               [value_in_use] 
        FROM   sys.configurations 
        WHERE  [name] = 'max server memory (MB)' 
        UNION ALL 
        SELECT 'Min_Server_Memory (MB)', 
               [value_in_use] 
        FROM   sys.configurations 
        WHERE  [name] = 'min server memory (MB)' 
        UNION ALL 
        SELECT 'BufferCacheHitRatio', 
               ( a.cntr_value * 1.0 / b.cntr_value ) * 100.0 
        FROM   sys.dm_os_performance_counters a 
               JOIN (SELECT cntr_value, 
                            object_name 
                     FROM   sys.dm_os_performance_counters 
                     WHERE  counter_name = 'Buffer cache hit ratio base' 
                            AND object_name = @Instancename + 'Buffer Manager') 
                    b 
                 ON a.object_name = b.object_name 
        WHERE  a.counter_name = 'Buffer cache hit ratio' 
               AND a.object_name = @Instancename + 'Buffer Manager') AS D; 

