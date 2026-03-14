-- Assignment 1 – Database Index Fragmentation Management with Cursor

/*

        ╔══╦═══════════════════════╦══╗
        ║░░║░░░░ Requirement 1 ░░░░║░░║
        ╚══╩═══════════════════════╝══╝

    1. Your cursor should retrieve all tables
    (user tables only, not system tables)
    that exist in the database you are currently connected to.

*/

-- Part 1: Variable Definition and initialization


DECLARE @start_time             DATETIME2 = SYSDATETIME();
DECLARE @end_time               DATETIME2;
DECLARE @elapsed_seconds        INT;

DECLARE @schema_name            SYSNAME;
DECLARE @prev_schema_name       SYSNAME;
DECLARE @table_name             SYSNAME;
DECLARE @prev_table_name        SYSNAME;
DECLARE @index_name             SYSNAME;

DECLARE @fragment_percentage    DECIMAL(5,2);
DECLARE @dynamic_sql            NVARCHAR(MAX);

DECLARE @total_tables_count     INT = 0;
DECLARE @total_indexes_count    INT = 0;
DECLARE @reorganized_idx_count  INT = 0;
DECLARE @rebuilt_idx_count      INT = 0;


-- Part 2: Declare cursor
-- Retrieves user tables and their indexes


/*

    • Uses sys.tables and sys.schemas
    • Joins to sys.indexes
    • Uses sys.dm_db_index_physical_stats
      It returns size and fragmentation
         information for the data and
         indexes of the specified table

    • Excludes system tables (is_ms_shipped = 0)
    • Ignores heaps (index_id = 0)
    • Ignores disabled indexes (is_disabled = 0)

*/

DECLARE index_cursor CURSOR FOR
SELECT
    s.name  AS schema_name,
    t.name  AS table_name,
    i.name  AS index_name,
    ips.avg_fragmentation_in_percent
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
JOIN sys.indexes i
    ON t.object_id = i.object_id
JOIN sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,           -- Limited parameter is limiting the scan to only the
    NULL,           -- parent-level pages above the leaf level and the
    'LIMITED'       -- leaf-level pages themselves, rather than scanning all pages.
) ips
    ON ips.object_id = i.object_id
   AND ips.index_id  = i.index_id
WHERE t.is_ms_shipped = 0
  AND i.index_id > 0
  AND i.is_disabled = 0
ORDER BY
    s.name,
    t.name,
    i.name;

/*
        ╔══╦════════════════════════╦══╗
        ║░░║░░░░ Requirement 2a ░░░░║░░║
        ╚══╩════════════════════════╝══╝

    2a. The cursor should iterate through the list of tables
       row by row...,
    
*/


OPEN index_cursor;

FETCH NEXT FROM index_cursor
INTO @schema_name, @table_name, @index_name, @fragment_percentage;

WHILE @@FETCH_STATUS = 0
BEGIN

-- The cursor iterates through indexes and the same table appears multiple times.
-- I therefore increment the table counter only when the table changes.
IF @prev_schema_name IS NULL
   OR @schema_name <> @prev_schema_name
   OR @table_name  <> @prev_table_name
BEGIN
    SET @total_tables_count += 1;

    SET @prev_schema_name = @schema_name;
    SET @prev_table_name  = @table_name;
END

    SET @total_indexes_count += 1;

    
    /*

        ╔══╦════════════════════════════╦══╗
        ║░░║░░░░ Requirement 2b + 3 ░░░░║░░║
        ╚══╩════════════════════════════╝══╝

2b. ... and check the level of fragmentation for the
        various indexes associated with each table.


Part 1: 3a. Indexes that are fragmented should be rebuilt or
        reorganized (depending on the level of fragmentation).
        Naturally, there must be some SQL code before the cursor
        (so that the cursor can function at all) and also SQL code after it.

    I use dynamic SQL to iterate through object names (schema, table, index)
    
    With dynamic SQL,

    • If fragmentation is BETWEEN 5 and 30 then REORGANIZE indexes

    • If fragmentation is ABOVE 30 then REBUILD indexes

    • Increment reorganized / rebuilt counters

*/
    -- QUOTENAME makes the input string a valid SQL Server delimited identifier.
    IF @fragment_percentage BETWEEN 5 AND 30
    BEGIN
        SET @dynamic_sql =
            'ALTER INDEX ' + QUOTENAME(@index_name) +
            ' ON ' + QUOTENAME(@schema_name) + '.' +
            QUOTENAME(@table_name) + ' REORGANIZE;';

        EXEC (@dynamic_sql);
        SET @reorganized_idx_count += 1;
    END
    ELSE IF @fragment_percentage > 30
    BEGIN
        SET @dynamic_sql =
            'ALTER INDEX ' + QUOTENAME(@index_name) +
            ' ON ' + QUOTENAME(@schema_name) + '.' +
            QUOTENAME(@table_name) + ' REBUILD;';

        EXEC (@dynamic_sql);
        SET @rebuilt_idx_count += 1;
    END

    FETCH NEXT FROM index_cursor
    INTO @schema_name, @table_name, @index_name, @fragment_percentage;
END

-- Close connection
CLOSE index_cursor;
DEALLOCATE index_cursor;


-- Part 2: Final status report

-- 3b. When the entire script has finished, it should present a compiled
--     and overall status report to the person who executed the cursor


SET @end_time = SYSDATETIME();
SET @elapsed_seconds = DATEDIFF(SECOND, @start_time, @end_time);

PRINT 'Status Report';
PRINT '--------------------------------------------------';
PRINT 'The script started at ' + CONVERT(VARCHAR(19), @start_time, 120);
PRINT 'and ended at ' + CONVERT(VARCHAR(19), @end_time, 120) + ',';
PRINT 'total execution time ' +
      CAST(@elapsed_seconds / 60.0 AS VARCHAR(10)) +
      ' minutes (' + CAST(@elapsed_seconds AS VARCHAR) + ' seconds)';
PRINT '';
PRINT 'In total, the script checked ' +
      CAST(@total_tables_count AS VARCHAR) + ' tables and ' +
      CAST(@total_indexes_count AS VARCHAR) + ' indexes';
PRINT CAST(@reorganized_idx_count AS VARCHAR) + ' indexes were reorganized';
PRINT CAST(@rebuilt_idx_count AS VARCHAR) + ' indexes were rebuilt';

-- After the first run, if no significant DML operation occurs which
-- leads to any fragmentation, the result on later runs will be the same.
