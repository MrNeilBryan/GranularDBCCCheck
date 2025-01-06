USE [SQLAdministration]
GO

/****** Object:  StoredProcedure [dbo].[usp_DBCC_Checks]    Script Date: 06/01/2025 09:59:06 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.usp_DBCC_Checks') IS NULL
BEGIN;
    DECLARE @Command NVARCHAR(4000) = 'CREATE PROC dbo.usp_DBCC_Checks AS SELECT 1 AS x';-- SET 
    EXEC sys.sp_executesql @stmt = @Command;
    PRINT 'Creating stored procedure dbo.usp_DBCC_Checks';
END;
ELSE
BEGIN
    PRINT 'Stored procedure dbo.usp_DBCC_Checks already exists';
END
GO


------------------------------------------------------------------------------------------------------------------------
-- Name:        dbo.usp_DBCC_Checks
-- Author:        Eitan Blumin/Neil Bryan
-- Date:        20241119
-- Description: This script is essentially a wrapper for the Hellengren DBCC CHECKDB script. It works at the object level
--              instead of the database level. It can be supplied with a time out, and when it doe time out, the next time
--                that it runs, it will just pick up form where it left off.
--                The script works by getting a list of objects (tables) in last checktable sequence, oldest to first, and then
--                run a DBCC CHECKTABLE. 
--                Of course he DBCC CEHCKDB does three things:
--                    1 - CHECKALLOC
--                    2 - CHECKCATALOG
--                    3 - CHECKTABLE
--                I have added code to check if the database has changed since the laster iteration, and if it has, and a CHECKCATALOG
--                or a CHECKALLOC has not run in the last day, then run a DBCC CHECKCATALOG and/or a DBCC CHECKDBCC.
--                Also note that the original Hellengren script/proc [dbo].[DatabaseIntegrityCheck] to do the work, and log to the
--                dbo.CommandLog table.
--
-- Amendments:
-- -----------
--
-- Who            When        Ref            Description
-- ---            ----        ---            -----------
--
------------------------------------------------------------------------------------------------------------------------
ALTER   PROCEDURE [dbo].[usp_DBCC_Checks]
    @MinutesToRunFor INT = 120
AS
BEGIN
    --------------------------------------------------------------------------------------------------------------------
    -- Locals
    --------------------------------------------------------------------------------------------------------------------
    DECLARE @ThisSqlFileName NVARCHAR(4000) = N'dbo.usp_DBCC_Checks';
    DECLARE @ProcessingStage NVARCHAR(4000) = NULL;
    DECLARE @SQLStartTime DATETIME = GETDATE();
    DECLARE @EndTime DATETIME = DATEADD(MINUTE, @MinutesToRunFor, GETDATE())  
    DECLARE @OlaHallengrenDBName SYSNAME = DB_NAME(); -- This script must run within the context of the database where Ola's maintenance solution was installed
    DECLARE @LastDatabaseProcessed NVARCHAR(256) = '';
    DECLARE @DBName SYSNAME;
    DECLARE @ObjNameFull NVARCHAR(4000);
    DECLARE @ObjNameLean SYSNAME;
    DECLARE @SchName SYSNAME;
    DECLARE @CheckTime DATETIME;
    DECLARE @LastCheckDate DATETIME;
    DECLARE @ObjType SYSNAME;
    DECLARE @CMD NVARCHAR(max);
    DECLARE @SpExecuteSql NVARCHAR(4000);



    --------------------------------------------------------------------------------------------------------------------
    -- Initialize
    --------------------------------------------------------------------------------------------------------------------
    SET NOCOUNT ON;

    --------------------------------------------------------------------------------------------------------------------
    -- Main processing and error handling start
    --------------------------------------------------------------------------------------------------------------------
    BEGIN TRY
        SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Starting.';
        RAISERROR (@ProcessingStage,10,1);

        --------------------------------------------------------------------------------------------------------------------
        -- Check for Hellengren
        --------------------------------------------------------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE OBJECT_SCHEMA_NAME([object_id]) = 'dbo' AND [name] = 'DatabaseIntegrityCheck')
        BEGIN;
            SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Hellengren script dbo.DatabaseIntegrityCheck not found.';
            RAISERROR (@ProcessingStage,16,1);
        END;

        --------------------------------------------------------------------------------------------------------------------
        -- Create a table to store all objects to check
        --------------------------------------------------------------------------------------------------------------------
        SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Create a table to store all objects to check.';
        RAISERROR (@ProcessingStage,10,1);
        IF OBJECT_ID('tempdb..#Objects') IS NOT NULL DROP TABLE #Objects;
        CREATE TABLE #Objects
        (
            DBName sysname,
            SchemaName sysname,
            TableName sysname,
            ObjType sysname,
            UsedPages int,
            LastCheck datetime,
            FullTableName AS (QUOTENAME(DBName) + N'.' + QUOTENAME(SchemaName) + '.' + QUOTENAME(TableName))
        );


        --------------------------------------------------------------------------------------------------------------------
        -- Get a list of objects to check
        --------------------------------------------------------------------------------------------------------------------
        SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Get a list of objects to check.';
        RAISERROR (@ProcessingStage,10,1);
        SET @CMD = N'SELECT DB_NAME()
        , ss.name
        , so.[name]
        , CASE WHEN so.[type] = ''V'' THEN ''VIEW'' ELSE ''TABLE'' END
        , SUM(sps.used_page_count) AS used_page_count
        , ep.[EndTime]
        FROM sys.objects so
        INNER JOIN sys.dm_db_partition_stats sps ON so.[object_id] = sps.[object_id]
        INNER JOIN sys.indexes si ON so.[object_id] = si.[object_id]
        INNER JOIN sys.schemas ss ON so.[schema_id] = ss.[schema_id]
        OUTER APPLY
        (
            SELECT [DatabaseName]
                  ,[SchemaName]
                  ,[ObjectName]
                  ,[ObjectType]
                  ,MAX([EndTime]) AS [EndTime]
            FROM ' + @OlaHallengrenDBName + N'.[dbo].[CommandLog]
            WHERE CommandType    = ''DBCC_CHECKTABLE''
            AND [DatabaseName]    COLLATE DATABASE_DEFAULT = DB_NAME() COLLATE DATABASE_DEFAULT
            AND [SchemaName]    COLLATE DATABASE_DEFAULT = ss.[name] COLLATE DATABASE_DEFAULT
            AND [ObjectName]    COLLATE DATABASE_DEFAULT = so.[name] COLLATE DATABASE_DEFAULT
            AND [ObjectType]    COLLATE DATABASE_DEFAULT = so.[type] COLLATE DATABASE_DEFAULT
            GROUP BY
                   [DatabaseName]
                  ,[SchemaName]
                  ,[ObjectName]
                  ,[ObjectType]
        ) AS ep
        WHERE so.[type] IN (''U'', ''V'')
        GROUP BY so.[object_id], so.[name], ss.name, so.[type], so.type_desc, ep.[EndTime]';

        DECLARE DBs CURSOR
        LOCAL FAST_FORWARD READ_ONLY
        FOR
        SELECT [name]
        FROM sys.databases
        WHERE HAS_DBACCESS([name]) = 1
        AND state = 0
        AND [name] NOT IN ('tempdb')

        OPEN DBs

        WHILE 1=1
        BEGIN
            FETCH NEXT FROM DBs INTO @DBName;
            IF @@FETCH_STATUS <> 0 BREAK;

            SET @SpExecuteSql = QUOTENAME(@DBName) + N'..sp_executesql'

            INSERT INTO #Objects
            (DBName, SchemaName, TableName, ObjType, UsedPages, LastCheck)
            EXEC @SpExecuteSql @CMD

        END
        CLOSE DBs;
        DEALLOCATE DBs;



        --------------------------------------------------------------------------------------------------------------------
        -- Check each object. Also do a CHECKALLOC and CHECKTABLE if need be.
        --------------------------------------------------------------------------------------------------------------------
        SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Check each object. Also do a CHECKALLOC and CHECKTABLE if need be.';
        RAISERROR (@ProcessingStage,10,1);
        DECLARE obj CURSOR
        LOCAL FAST_FORWARD READ_ONLY
        FOR
        SELECT DBName,FullTableName,SchemaName,TableName,ObjType,LastCheck
        FROM #Objects
        ORDER BY LastCheck ASC, UsedPages DESC

        OPEN obj;

        WHILE GETDATE() < @EndTime
        BEGIN
            FETCH NEXT FROM obj INTO @DBName, @ObjNameFull, @SchName, @ObjNameLean, @ObjType, @LastCheckDate;
            IF @@FETCH_STATUS <> 0 
            BEGIN;
                BREAK;
            END;


            --------------------------------------------------------------------------------------------------------------------
            -- If the database has changed from the last iteration AND the last check check alloc was more than a week ago
            --------------------------------------------------------------------------------------------------------------------
            IF @DBName <> @LastDatabaseProcessed
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.CommandLog WHERE DatabaseName = @DBName AND CommandType = 'DBCC_CHECKALLOC' AND StartTime < DATEADD(DAY,-1,GETDATE()) AND EndTime IS NOT NULL AND ErrorNumber = 0 )
                BEGIN
                    SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Running CHECKALLOC on database ' + @DBName + ' .';
                    RAISERROR (@ProcessingStage,10,1);
                    EXEC [dbo].[DatabaseIntegrityCheck]
                            @Databases = @DBName,
                            @CheckCommands = 'CHECKALLOC',
                            @Execute = 'Y',
                            @LogToTable = 'Y';
                END;

                IF NOT EXISTS (SELECT 1 FROM dbo.CommandLog WHERE DatabaseName = @DBName AND CommandType = 'DBCC_CHECKCATALOG' AND StartTime < DATEADD(DAY,-1,GETDATE()) AND EndTime IS NOT NULL AND ErrorNumber = 0 )
                BEGIN
                    SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Running CHECKCATALOG on database ' + @DBName + ' .';
                    RAISERROR (@ProcessingStage,10,1);
                    EXEC [dbo].[DatabaseIntegrityCheck]
                            @Databases = @DBName,
                            @CheckCommands = 'CHECKCATALOG',
                            @Execute = 'Y',
                            @LogToTable = 'Y';
                END;
            END;

            --------------------------------------------------------------------------------------------------------------------
            -- Run the check table
            --------------------------------------------------------------------------------------------------------------------
            EXEC [dbo].[DatabaseIntegrityCheck]
                @Databases = @DBName,
                @CheckCommands = 'CHECKTABLE',
                @Objects = @ObjNameFull,
                @Execute = 'Y',
                @LogToTable = 'Y';

            SET @LastDatabaseProcessed = @DBName;
        END;
        CLOSE obj;
        DEALLOCATE obj;


        ----------------------------------------------------------------------------------------------------------------
        -- Finish
        ----------------------------------------------------------------------------------------------------------------
        SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Completed in ' + CAST(DATEDIFF(SECOND, @SQLStartTime, GETDATE()) AS NVARCHAR(256)) + N' seconds.';
        RAISERROR (@ProcessingStage,10,1);
    END TRY

    BEGIN CATCH
        DECLARE @CatchErrorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
        DECLARE @CatchMessage NVARCHAR(MAX) = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Last Recored Stage:' + COALESCE(@ProcessingStage, N'[NONE]') + N' Running time: ' + CAST(DATEDIFF(SECOND, @SQLStartTime, GETDATE()) AS NVARCHAR(256)) + N' seconds.' + N' - Error Message:' + @CatchErrorMessage;

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK;
            SET @CatchMessage += N' - Transaction(s) rolled back.'
        END;

        RAISERROR (@CatchMessage,16,1);
    END CATCH
END
GO
