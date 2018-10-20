/****** Object:  StoredProcedure [dbo].[CURRENT_proc_dev_generic_table_replacement]    Script Date: 10/19/2018 2:34:53 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



-- 	Dev Start: May 11th, 2018
-- 	by ACCOUNTS\jyotideepta

-- 	Procedure to retire (but not remove) old tables with new development 
-- 	tables.

--	Use Case:

--	Replacing an old table with bad data being used in an production environment
--	where the table is connected to and necessary for numerous other database objects.
-- 	This procedure allows for such tables to be easy swapped with a new table of
-- 	better data.

-- 	For this procedure to work there are some initial requirements
-- 	(the code won't do anything unless each is met).

--	1. DEV table name: InDevelopment_<old table name>
-- 	2. The DEV table must contain all of the OLD tables columns
--	3. For data integrity, the new DEV_id has to be the range of atleast
--	********90%******** of OLD_id.
--	4. OLD table must have a column newtable_<PK name> which serves as the
--	link between OLD_id in the OLD table and DEV_id in the DEV table.


CREATE PROCEDURE [dbo].[proc_generic_table_replacement]
	@oldTableName nvarchar(30)
AS
	-- Algorithm variables in order of appearance in code.
	DECLARE @devTableName 				nvarchar(50);
	DECLARE @tablesExist 				bit;
	DECLARE @columnsOld		table		(COLUMN_NAME nvarchar(60));
	DECLARE @columnsDev		table 		(COLUMN_NAME nvarchar(60));
	DECLARE @isSubset					bit;
	DECLARE @oldPrimaryKeyName			nvarchar(60);
	DECLARE @newPrimaryKeyName			nvarchar(60);
	DECLARE @newPrimaryKeyExists		bit;
	DECLARE @devPrimaryKeyName			nvarchar(60);
	DECLARE @isSurjective	table		(counts int);
	
	DECLARE @IDColumns		table		(old_id int, new_id int);
	DECLARE @dataHealth					DECIMAL(4,2);
	DECLARE @currTableName				nvarchar(60);
	CREATE TABLE #currTable				(curr_id int, mod_id int);

	
	
	/*--------------------------------------------
			CHECKS BEFORE RUNNING ALGORITHM
	--------------------------------------------*/
	
	-- Get dev table name based on naming criteria
	SET @devTableName = CONCAT('InDevelopment_', @oldTableName);
	
	-- Check if both tables exists as currently named
	SET @tablesExist = (	SELECT 1 
						FROM INFORMATION_SCHEMA.TABLES 
						WHERE TABLE_SCHEMA = 'dbo' 
						AND  TABLE_NAME = @devTableName
						INTERSECT 
						SELECT 1
						FROM INFORMATION_SCHEMA.TABLES 
						WHERE TABLE_SCHEMA = 'dbo' 
						AND  TABLE_NAME = @oldTableName
	);
	
	IF (@tablesExist IS NULL)
		BEGIN
		PRINT 'Tables not found in Information Schema. Please ensure table names are accurate. The new table should be named InDevelopment_<old table name>'
		RETURN
		END
	ELSE 
		BEGIN
		
		-- Check if columns exists
		INSERT INTO @columnsOld SELECT COLUMN_NAME
							from INFORMATION_SCHEMA.COLUMNS
							where TABLE_NAME = @oldTableName;
		INSERT INTO @columnsDev SELECT COLUMN_NAME
							from INFORMATION_SCHEMA.COLUMNS
							where TABLE_NAME = @devTableName;
		 
		SET @isSubset = ( SELECT (count(1) - 1) FROM @columnsOld -- -1 to account for the additional newtable_ id col in old table
								INTERSECT 
								SELECT count(1) FROM @columnsOld
								WHERE COLUMN_NAME IN 
								(SELECT * FROM @columnsDev));
		
		IF (@isSubset IS NULL OR @isSubset = 0)
			BEGIN
			PRINT 'Old table not subset of dev table. Please ensure that all old table columns exist in dev table.'
			RETURN
			END
		ELSE
			BEGIN
			-- For Surjection property, first make sure oldtable_<PK name> exists in dev table
				
			-- Get names of target columns	
			-- @@RESTRICTION: Target old ID column must be PK.
			SET @oldPrimaryKeyName = (SELECT COLUMN_NAME
			FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
			WHERE OBJECTPROPERTY(OBJECT_ID(CONSTRAINT_SCHEMA + '.' + QUOTENAME(CONSTRAINT_NAME)), 'IsPrimaryKey') = 1
			AND TABLE_NAME = @oldTableName AND TABLE_SCHEMA = 'dbo')
			
			SET @newPrimaryKeyName = CONCAT('newtable_',@oldPrimaryKeyName);
			
			SET @newPrimaryKeyExists = ( SELECT 1
											FROM INFORMATION_SCHEMA.COLUMNS
											where TABLE_NAME = @oldTableName
											AND COLUMN_NAME = @newPrimaryKeyName
			);
			
			IF (@newPrimaryKeyExists != 1)
				BEGIN
				PRINT 'OLD tables ID not found in Dev table. Please ensure there is a column linking old table"s id with dev tables id IN THE DEV TABLE'
				RETURN
				END
			ELSE 
				BEGIN

				-- Lastly, need to ensure that the new table accounts for a large portion,
				-- if not all of the old tables data by checking the two linking columns.
				
				-- Get the ID columns from the old table:
				
				INSERT INTO @IDColumns EXEC('SELECT '+@oldPrimaryKeyName+', '+@newPrimaryKeyName+'
				FROM '+@oldTableName
				);
				
				DECLARE @dataCountOld int = (SELECT count(1) 
							FROM @IDColumns 
							WHERE old_id IS NOT NULL 
							AND old_id != ''
							);
				DECLARE @dataCountNew int = (SELECT count(1) 
							FROM @IDColumns 
							WHERE new_id IS NOT NULL 
							AND new_id != ''
							);

				-- COMPUTE DATA HEALTH			
				SET @dataHealth = (@dataCountNew*100)/CAST(@dataCountOld AS DECIMAL(5,2));
				
				IF (@dataHealth > 90)
					BEGIN
					PRINT 'Data Matched: ' + CAST(@dataHealth AS VARCHAR) + '%'
					-- ALL REQUIREMENTS MET, UPDATE IDs WHEREVER POSSIBLE.

					DECLARE @FKColumnName nvarchar(50) = CONCAT('fk_', @oldPrimaryKeyName);
					
					DECLARE cur_tables CURSOR FAST_FORWARD READ_ONLY
					FOR SELECT TABLE_NAME AS 'TableName'
					FROM	INFORMATION_SCHEMA.COLUMNS
					WHERE	COLUMN_NAME = @FKColumnName;
					
					OPEN cur_tables;
					FETCH NEXT FROM cur_tables INTO
						@currTableName;
					
					WHILE @@FETCH_STATUS = 0
						BEGIN
						
						-- UPDATE IDs:
						-- GET ID TO BE REPLACED
							--FOR DEBUGGING;						
						SELECT @currTableName as 'CURRENT TABLE';
						SELECT 'CURRENT DATA';
						EXEC('SELECT * FROM '+@currTableName+' order by '+@FKColumnName);

						INSERT INTO #currTable (curr_id) EXEC('SELECT DISTINCT '+@FKColumnName+' FROM '+@currTableName+ '');

						
						UPDATE #currTable 
						SET mod_id = new_id
						FROM @IDColumns
						WHERE curr_id = old_id;

						SELECT curr_id as 'OLD ID', mod_id as 'NEW ID' FROM #currTable;

						EXEC ('UPDATE '+@currTableName+'
						SET '+@FKColumnName+' = mod_id
						FROM #currTable
						WHERE '+@FKColumnName+' = curr_id');

						SELECT 'MODIFIED ' + @currTableName;

						-- Delete everything from table variable to make space for next loop
						DELETE FROM #currTable;

						-- GET NEXT
						FETCH NEXT FROM cur_tables INTO 
							@currTableName;			
						
						/* END Process CURSOR */
						END;
					CLOSE cur_tables;
					DEALLOCATE cur_tables;
					

					-- RENAME tables
					DECLARE @renameOld VARCHAR(100);
					DECLARE @renameNew VARCHAR(100);
					SELECT @renameOld = 'OLD' + @oldTableName, @renameNew = @oldTableName;
					EXEC sp_rename @oldTableName, @renameOld;
					EXEC sp_rename @devTableName, @renameNew;

					DROP TABLE #currTable;

					END
				
				ELSE
					BEGIN
					PRINT 'ID Column not sufficiently linked. Data Matched: ' + CAST(@dataHealth AS VARCHAR) + '%. Need > 90% match. No changes made.'
					RETURN
					END;
				END
			END;
		END;
		
	RETURN 0;
	
GO


