
IF  EXISTS (
	SELECT 1
	FROM sys.objects
	WHERE object_id = OBJECT_ID(N'[dbo].[SafeDropDatabase]') AND type IN (N'P', N'PC')
)
    DROP PROCEDURE [dbo].[SafeDropDatabase];

GO

-- This is a procedure to drop a database.
-- Out of life’s school of war — Droping a database is not always straightforward.
-- This procedure was created around 2016 through experimentation.
-- I do not mean every thing in this procedure is still correct and needed nowadays.
-- Execute this script on the master database to install.
CREATE PROCEDURE dbo.SafeDropDatabase @DatabaseName NVARCHAR(1024)
AS
BEGIN

	-- Delete database snapshots
	DECLARE snapshotsCursor CURSOR FOR
	SELECT name
	FROM sys.databases db
	WHERE source_database_id = (SELECT database_id FROM sys.databases sdb WHERE sdb.name = @DatabaseName)

	DECLARE @snapshotDropQuery NVARCHAR(4000);
	DECLARE @snapshotName NVARCHAR(4000);

	OPEN snapshotsCursor

	FETCH NEXT FROM snapshotsCursor INTO @snapshotName
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @snapshotDropQuery = 'DROP DATABASE [' + @snapshotName + ']';
		PRINT(@snapshotDropQuery);
		EXECUTE(@snapshotDropQuery);
		FETCH NEXT FROM statsJobsCursor INTO @snapshotName
	END

	CLOSE snapshotsCursor
	DEALLOCATE snapshotsCursor

	-- Disable statistics asynchronous auto updates.
	DECLARE @DisableAsyncStatsQuery NVARCHAR(4000);
	SET @DisableAsyncStatsQuery = 'ALTER DATABASE [' + @DatabaseName + '] SET AUTO_UPDATE_STATISTICS_ASYNC OFF';
	PRINT(@DisableAsyncStatsQuery);
	EXECUTE(@DisableAsyncStatsQuery);

	-- Kill stats jobs.
	DECLARE statsJobsCursor CURSOR FOR
	SELECT job_id
	FROM sys.dm_exec_background_job_queue ebgq
	INNER JOIN sys.databases db
		ON db.database_id = ebgq.database_id
	WHERE db.name = @DatabaseName;

	DECLARE @KillStatsJobQuery NVARCHAR(4000);
	DECLARE @statsJobId INT;

	OPEN statsJobsCursor

	FETCH NEXT FROM statsJobsCursor INTO @statsJobId
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @KillStatsJobQuery = 'KILL STATS JOB ' + STR(@statsJobId)
		PRINT(@KillStatsJobQuery);
		EXECUTE(@KillStatsJobQuery);
		FETCH NEXT FROM statsJobsCursor INTO @statsJobId
	END

	CLOSE statsJobsCursor
	DEALLOCATE statsJobsCursor

	-- Kill processes.
	DECLARE processesCursor CURSOR FOR
	SELECT
		CONVERT(SMALLINT, req_spid) AS spid
	FROM master.dbo.syslockinfo l
	INNER JOIN master.dbo.spt_values v
		ON l.rsc_type = v.number AND v.type = 'LR' 
	INNER JOIN master.dbo.spt_values x
		ON l.req_status = x.number AND x.type = 'LS'
	INNER JOIN master.dbo.spt_values u
		ON l.req_mode + 1 = u.number AND u.type = 'L'
	WHERE l.rsc_dbid = (SELECT TOP 1 dbid FROM master..sysdatabases WHERE name = @DatabaseName)


	DECLARE @KillProcessesQuery NVARCHAR(4000);
	DECLARE @spid INT;

	OPEN processesCursor

	FETCH NEXT FROM processesCursor INTO @spid
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @KillProcessesQuery = 'KILL ' + STR(@spid)
		PRINT(@KillProcessesQuery);
		EXECUTE(@KillProcessesQuery);
		FETCH NEXT FROM processesCursor INTO @spid
	END

	CLOSE processesCursor
	DEALLOCATE processesCursor

	-- Switch the database to single user mode.
	DECLARE @SingleUserQuery NVARCHAR(4000);
	SET @SingleUserQuery = 'ALTER DATABASE [' + @DatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE';
	PRINT(@SingleUserQuery);
	EXECUTE(@SingleUserQuery);

	-- Rename the database to be dropped.
	DECLARE @RenameDatabaseQuery NVARCHAR(4000);
	SET @RenameDatabaseQuery = 'ALTER DATABASE [' + @DatabaseName + '] MODIFY NAME = [DROP_' + @DatabaseName + ']';
	PRINT(@RenameDatabaseQuery);
	EXECUTE(@RenameDatabaseQuery);

	-- Drop the renamed database.
	DECLARE @DropDatabaseQuery NVARCHAR(4000);
	SET @DropDatabaseQuery = 'DROP DATABASE [DROP_' + @DatabaseName + ']';
	PRINT(@DropDatabaseQuery);
	EXECUTE(@DropDatabaseQuery);

END;

GO
