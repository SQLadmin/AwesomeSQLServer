--==============================================--
/*** SQL SERVER Disk Space Monitoring QUERIES ***/
--==============================================--

-- Supported Versions SQL server 2008 and higher
-------------------------------------------------

----------------------------------------------
/*** 1. Get all Disks Total and Free Size ***/
----------------------------------------------


DECLARE @MOUNTVOL TABLE
 ( MOUNTVOLResult nVARCHAR(500)
  ,ExecCommand nVARCHAR(500))
  
INSERT INTO @MOUNTVOL (MOUNTVOLResult) 
EXEC XP_CMDSHELL 'MOUNTVOL'
  
DELETE @MOUNTVOL WHERE MOUNTVOLResult LIKE '%VOLUME%'
DELETE @MOUNTVOL WHERE MOUNTVOLResult IS NULL
DELETE @MOUNTVOL WHERE MOUNTVOLResult NOT LIKE '%:%'
DELETE @MOUNTVOL WHERE MOUNTVOLResult LIKE '%MOUNTVOL%'
DELETE @MOUNTVOL WHERE MOUNTVOLResult LIKE '%RECYCLE%'
  
UPDATE @MOUNTVOL SET ExecCommand = 'EXEC XP_CMDSHELL ''FSUTIL VOLUME DISKFREE ' + LTRIM(RTRIM(MOUNTVOLResult)) +''''
  
DECLARE @DRIVESpace TABLE
 ( DriveLetter VARCHAR(10)
  ,DriveInfo VARCHAR(100))
    
WHILE (SELECT COUNT(*) FROM @MOUNTVOL) <>0
BEGIN
 DECLARE @Command nVARCHAR(500), @DriveLetter nVARCHAR(10)
 Select @Command = ExecCommand, @DriveLetter= MOUNTVOLResult from @MOUNTVOL
 INSERT INTO @DRIVESpace (DriveInfo) Exec sp_executeSQL @Command
 UPDATE @DRIVESpace SET DriveLetter=@DriveLetter WHERE DriveLetter IS NULL
 DELETE FROM @MOUNTVOL WHERE ExecCommand=@Command
END
  
DECLARE @FinalResults TABLE
 ( DriveLetter nVARCHAR(10)
  ,[TotalDriveSpace(MB)] DECIMAL(18,2)
  ,[UsedSpaceOnDrive(MB)] AS ([TotalDriveSpace(MB)] - [FreeSpaceOnDrive(MB)])
  ,[FreeSpaceOnDrive(MB)] DECIMAL(18,2)
  ,[TotalDriveSpace(GB)] AS CAST(([TotalDriveSpace(MB)]/1024) AS DECIMAL(18,2))
  ,[UsedSpaceOnDrive(GB)] AS CAST((([TotalDriveSpace(MB)] - [FreeSpaceOnDrive(MB)])/1024) AS DECIMAL(18,2))
  ,[FreeSpaceOnDrive(GB)] AS CAST(([FreeSpaceOnDrive(MB)]/1024) AS DECIMAL(18,2))
  ,[%FreeSpace] AS CAST((([FreeSpaceOnDrive(MB)]/[TotalDriveSpace(MB)])*100) AS DECIMAL(18,2)))
  
INSERT INTO @FinalResults (DriveLetter, [TotalDriveSpace(MB)],[FreeSpaceOnDrive(MB)])
SELECT RTRIM(LTRIM(DriveLetter))
    ,[TotalDriveSpace(MB)] = SUM(CASE WHEN DriveInfo LIKE 'TOTAL # OF BYTES%' THEN CAST(SUBSTRING(DriveInfo, 32, 48) AS FLOAT) ELSE CAST(0 AS FLOAT) END)/1024/1024
    ,[FreeSpaceOnDrive(MB)] = SUM(CASE WHEN DriveInfo LIKE 'TOTAL # OF FREE BYTES%' THEN CAST(SUBSTRING(DriveInfo, 32, 48) AS FLOAT) ELSE CAST(0 AS FLOAT) END)/1024/1024
FROM @DRIVESpace
WHERE DriveInfo LIKE 'TOTAL # OF %'
GROUP BY DriveLetter
ORDER BY DriveLetter
  
SELECT DriveLetter, [TotalDriveSpace(GB)], [TotalDriveSpace(GB)], [%FreeSpace] FROM @FinalResults


-------------------------------------------------
/*** 2. Get databases physical file location ***/
-------------------------------------------------

SELECT DISTINCT Db_name(dovs.database_id) 
                [Database Name], 
                mf.physical_name 
                [Physical File Location], 
                dovs.logical_volume_name                              AS 
                [Logical Name], 
                dovs.volume_mount_point                               AS Drive, 
                CONVERT(INT, dovs.available_bytes / 1048576.0 / 1024) AS 
                [Free Space (GB)] 
FROM   sys.master_files mf 
       CROSS apply sys.Dm_os_volume_stats(mf.database_id, mf.file_id) dovs 
ORDER  BY [free space (gb)] ASC 


----------------------------------------------
/*** 3. List all Databases and its file size ***/
----------------------------------------------

--Data file size

IF EXISTS (SELECT
    *
  FROM tempdb.sys.all_objects
  WHERE name LIKE '%#dbsize%')
  DROP TABLE #dbsize
CREATE TABLE #dbsize (
  Dbname sysname,
  dbstatus varchar(50),
  Recovery_Model varchar(40) DEFAULT ('NA'),
  file_Size_MB decimal(30, 2) DEFAULT (0),
  Space_Used_MB decimal(30, 2) DEFAULT (0),
  Free_Space_MB decimal(30, 2) DEFAULT (0)
)
GO

INSERT INTO #dbsize (Dbname, dbstatus, Recovery_Model, file_Size_MB, Space_Used_MB, Free_Space_MB)
EXEC sp_msforeachdb 'use [?]; 
  select DB_NAME() AS DbName, 
    CONVERT(varchar(20),DatabasePropertyEx(''?'',''Status'')) ,  
    CONVERT(varchar(20),DatabasePropertyEx(''?'',''Recovery'')),  
sum(size)/128.0 AS File_Size_MB, 
sum(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS INT))/128.0 as Space_Used_MB, 
SUM( size)/128.0 - sum(CAST(FILEPROPERTY(name,''SpaceUsed'') AS INT))/128.0 AS Free_Space_MB  
from sys.database_files  where type=0 group by type'





GO

-- log file size

IF EXISTS (SELECT
    *
  FROM tempdb.sys.all_objects
  WHERE name LIKE '#logsize%')
  DROP TABLE #logsize
CREATE TABLE #logsize (
  Dbname sysname,
  Log_File_Size_MB decimal(38, 2) DEFAULT (0),
  log_Space_Used_MB decimal(30, 2) DEFAULT (0),
  log_Free_Space_MB decimal(30, 2) DEFAULT (0)
)
GO

INSERT INTO #logsize (Dbname, Log_File_Size_MB, log_Space_Used_MB, log_Free_Space_MB)
EXEC sp_msforeachdb 'use [?]; 
  select DB_NAME() AS DbName, 
sum(size)/128.0 AS Log_File_Size_MB, 
sum(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS INT))/128.0 as log_Space_Used_MB, 
SUM( size)/128.0 - sum(CAST(FILEPROPERTY(name,''SpaceUsed'') AS INT))/128.0 AS log_Free_Space_MB  
from sys.database_files  where type=1 group by type'


GO

-- database free size 

IF EXISTS (SELECT
    *
  FROM tempdb.sys.all_objects
  WHERE name LIKE '%#dbfreesize%')
  DROP TABLE #dbfreesize
CREATE TABLE #dbfreesize (
  name sysname,
  database_size varchar(50),
  Freespace varchar(50) DEFAULT (0.00)
)

INSERT INTO #dbfreesize (name, database_size, Freespace)
EXEC sp_msforeachdb 'use [?];SELECT database_name = db_name() 
    ,database_size = ltrim(str((convert(DECIMAL(15, 2), dbsize) + convert(DECIMAL(15, 2), logsize)) * 8192 / 1048576, 15, 2) + ''MB'') 
    ,''unallocated space'' = ltrim(str(( 
                CASE  
                    WHEN dbsize >= reservedpages 
                        THEN (convert(DECIMAL(15, 2), dbsize) - convert(DECIMAL(15, 2), reservedpages)) * 8192 / 1048576 
                    ELSE 0 
                    END 
                ), 15, 2) + '' MB'') 
FROM ( 
    SELECT dbsize = sum(convert(BIGINT, CASE  
                    WHEN type = 0 
                        THEN size 
                    ELSE 0 
                    END)) 
        ,logsize = sum(convert(BIGINT, CASE  
                    WHEN type <> 0 
                        THEN size 
                    ELSE 0 
                    END)) 
    FROM sys.database_files 
) AS files 
,( 
    SELECT reservedpages = sum(a.total_pages) 
        ,usedpages = sum(a.used_pages) 
        ,pages = sum(CASE  
                WHEN it.internal_type IN ( 
                        202 
                        ,204 
                        ,211 
                        ,212 
                        ,213 
                        ,214 
                        ,215 
                        ,216 
                        ) 
                    THEN 0 
                WHEN a.type <> 1 
                    THEN a.used_pages 
                WHEN p.index_id < 2 
                    THEN a.data_pages 
                ELSE 0 
                END) 
    FROM sys.partitions p 
    INNER JOIN sys.allocation_units a 
        ON p.partition_id = a.container_id 
    LEFT JOIN sys.internal_tables it 
        ON p.object_id = it.object_id 
) AS partitions'




IF EXISTS (SELECT
    *
  FROM tempdb.sys.all_objects
  WHERE name LIKE '%#alldbstate%')
  DROP TABLE #alldbstate
CREATE TABLE #alldbstate (
  dbname sysname,
  DBstatus varchar(55),
  R_model varchar(30)
)

--select * from sys.master_files 

INSERT INTO #alldbstate (dbname, DBstatus, R_model)
  SELECT
    name,
    CONVERT(varchar(20), DATABASEPROPERTYEX(name, 'status')),
    recovery_model_desc
  FROM sys.databases
--select * from #dbsize 

INSERT INTO #dbsize (Dbname, dbstatus, Recovery_Model)
  SELECT
    dbname,
    dbstatus,
    R_model
  FROM #alldbstate
  WHERE DBstatus <> 'online'

INSERT INTO #logsize (Dbname)
  SELECT
    dbname
  FROM #alldbstate
  WHERE DBstatus <> 'online'

INSERT INTO #dbfreesize (name)
  SELECT
    dbname
  FROM #alldbstate
  WHERE DBstatus <> 'online'

SELECT

  d.Dbname AS [Database Name],
  d.dbstatus AS [Status],
  d.Recovery_Model AS [Recovery Mode],
  (file_size_mb + log_file_size_mb) AS [Total DB Size],
  fs.Freespace AS [DB Free Space],
  d.file_Size_MB AS [MDF Size(MB)],
  d.Space_Used_MB AS [MDF Used(MB)],
  d.Free_Space_MB AS [MDF Free(MB)],
  l.Log_File_Size_MB AS [LDF Size (MB)],
  log_Space_Used_MB AS [LDF Used (MB)],
  l.log_Free_Space_MB AS [LDF Free (MB)]
FROM #dbsize d
JOIN #logsize l
  ON d.Dbname = l.Dbname
JOIN #dbfreesize fs
  ON d.Dbname = fs.name
ORDER BY [Database Name] ASC

