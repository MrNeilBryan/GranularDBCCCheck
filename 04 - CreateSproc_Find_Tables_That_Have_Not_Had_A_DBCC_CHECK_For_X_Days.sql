IF OBJECT_ID('dbo.usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days') IS NULL
BEGIN
		;

	DECLARE @Command NVARCHAR(4000) = 'CREATE PROC dbo.usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days AS SELECT 1 AS x';-- SET 

	EXEC sys.sp_executesql @stmt = @Command;

	PRINT 'Creating stored procedure dbo.usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days';
END;
ELSE
BEGIN
	PRINT 'Stored procedure dbo.usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days already exists';
END
GO

------------------------------------------------------------------------------------------------------------------------
-- Name: dbo.usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days
-- Author: Neil Bryan
-- Date: 20250106
-- Description: Find all tables that have not had a DBCC CHECK for 
--
-- Amendments:
-- -----------
--
-- Who When Ref Description
-- --- ---- --- -----------
--
------------------------------------------------------------------------------------------------------------------------
ALTER PROCEDURE [dbo].[usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days] @DaysBack 
	@DaysBack INT = -14, @NumberOfRecords INT OUTPUT
AS
BEGIN
	--------------------------------------------------------------------------------------------------------------------
	-- Locals
	--------------------------------------------------------------------------------------------------------------------
	DECLARE @ThisSqlFileName NVARCHAR(4000) = N'dbo.usp_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days';
	DECLARE @ProcessingStage NVARCHAR(4000) = NULL;
	DECLARE @SQLStartTime DATETIME = GETDATE();
	DECLARE @DatabaseName NVARCHAR(256) = N'';
	DECLARE @Results TABLE (DatabaseName NVARCHAR(256), SchemaName NVARCHAR(256), TableName NVARCHAR(256), LastDBCCTableCheck DATETIME);
	DECLARE @Stmt NVARCHAR(4000) = N'';
	DECLARE @Template NVARCHAR(4000) = N'
USE [__DATABASENAME__]
;WITH _CommandLog AS
(
SELECT Databasename, 
SchemaName, 
ObjectName AS TableName, 
MAX(StartTime) AS LastDBCCTableCheck
FROM sqladministration.dbo.commandlog 
WHERE CommandType = ''DBCC_CHECKTABLE''
AND Databasename = DB_NAME()
GROUP BY Databasename, 
SchemaName, 
ObjectName
)
, _Tables AS
(
SELECT OBJECT_SCHEMA_NAME([object_id]) AS SchemaName, [Name] AS TableName FROM sys.tables
)


SELECT DB_NAME(), _Tables.*, _CommandLog.LastDBCCTableCheck 
FROM _Tables 
LEFT JOIN _CommandLog ON _Tables.TableName = _CommandLog.TableName AND _Tables.SchemaName = _CommandLog.SchemaName
WHERE LastDBCCTableCheck < DATEADD(DAY,__DAYSBACK__,GETDATE()) 
ORDER BY _CommandLog.LastDBCCTableCheck DESC';

	--------------------------------------------------------------------------------------------------------------------
	-- Initialize
	--------------------------------------------------------------------------------------------------------------------
	SET NOCOUNT ON;

	--------------------------------------------------------------------------------------------------------------------
	-- Main processing and error handling start
	--------------------------------------------------------------------------------------------------------------------
	BEGIN TRY
		SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Starting.';

		RAISERROR (@ProcessingStage, 10, 1);

		--------------------------------------------------------------------------------------------------------------------
		-- Iterate over each database
		--------------------------------------------------------------------------------------------------------------------
		SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Iterate over each database.';

		RAISERROR (@ProcessingStage, 10, 1);

		DECLARE cu CURSOR
		FOR
		SELECT [name]
		FROM sys.databases
		WHERE name <> 'tempdb'
		ORDER BY [name];

		OPEN cu

		FETCH cu
		INTO @DatabaseName;

		WHILE @@FETCH_STATUS <> - 1
		BEGIN
			SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Process database: ' + @DatabaseName;

			RAISERROR (@ProcessingStage, 10, 1);

			SET @Stmt = REPLACE(@Template, '__DATABASENAME__', @DatabaseName);
			SET @Stmt = Replace(@stmt, '__DAYSBACK__', CAST(@DaysBack AS NVARCHAR(256)));

			INSERT @Results (DatabaseName, SchemaName, TableName, LastDBCCTableCheck)
			EXEC sp_executesql @stmt = @stmt;

			FETCH cu
			INTO @DatabaseName;
		END

		CLOSE cu;

		DEALLOCATE cu;

		--------------------------------------------------------------------------------------------------------------------
		-- Show results
		--------------------------------------------------------------------------------------------------------------------
		SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Show Results.';

		RAISERROR (@ProcessingStage, 10, 1);

		SELECT * FROM @Results;
		SELECT @NumberOfRecords = COUNT(1) FROM @Results;

		----------------------------------------------------------------------------------------------------------------
		-- Finish
		----------------------------------------------------------------------------------------------------------------
		SET @ProcessingStage = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Completed in ' + CAST(DATEDIFF(SECOND, @SQLStartTime, GETDATE()) AS NVARCHAR(256)) + N' seconds.';

		RAISERROR (@ProcessingStage, 10, 1);
	END TRY

	BEGIN CATCH
		DECLARE @CatchErrorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
		DECLARE @CatchMessage NVARCHAR(MAX) = CONVERT(NVARCHAR(4000), GETDATE(), 121) + N' - ' + @ThisSqlFileName + N' - Last Recored Stage:' + COALESCE(@ProcessingStage, N'[NONE]') + N' Running time: ' + CAST(DATEDIFF(SECOND, @SQLStartTime, GETDATE()) AS NVARCHAR(256)) + N' seconds.' + N' - Error Message:' + @CatchErrorMessage;

		IF (@@TRANCOUNT > 0)
		BEGIN
			ROLLBACK;

			SET @CatchMessage += N' - Transaction(s) rolled back.'
		END;

		RAISERROR (@CatchMessage, 16, 1);
	END CATCH
END
GO

