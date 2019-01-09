USE [SS_Unit_Discovery]
GO

/****** Object:  UserDefinedFunction [dbo].[udf_Split_String_List]    Script Date: 1/9/2019 2:00:57 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[udf_Split_String_List]	( 
	@rowKey nvarchar(255), 
	@valueList nvarchar(max),
	@separator nvarchar(1)
)
RETURNS @result TABLE	(
    rowKey    varchar(255) not null,
    rowValue   varchar(255) not null
)
AS

BEGIN

DECLARE @Count int;				-- DECLARE variables for processing
DECLARE @currRowValue nvarchar(255);


-- Get count of values in list from current cursor cell:
IF (LTRIM(RTRIM(@valueList)) IS NOT NULL)
SET @Count = (SELECT (LEN(@valueList) - LEN(REPLACE(@valueList, @separator, '')) + 1));

-- Handle single instance entries
IF (@Count = 1) 
BEGIN
	SET @currRowValue = LTRIM(RTRIM(@valueList));
	INSERT INTO @result
	SELECT @rowKey, @currRowValue;
	
	SET @currRowValue = NULL;					-- RESET VARIABLE
END;

-- Handle multiple SIDHistory Entries
ELSE
BEGIN
-- Start loop based on counter value:
WHILE (@Count > 0 AND @Count IS NOT NULL AND RTRIM(LTRIM(@valueList)) != '')
	BEGIN
		-- GET Individual SIDHistory
		SET @currRowValue = (SELECT CASE WHEN CHARINDEX(@separator,@valueList) != 0 THEN RTRIM(LTRIM(SUBSTRING(@valueList,1,ISNULL(CHARINDEX(@separator, @valueList) - 1, LEN(@valueList)))))
									ELSE @valueList END);
		-- RESET @currSIDHistoryList by removing extracted SIDHistory
		SET @valueList = (SELECT RTRIM(LTRIM(SUBSTRING(@valueList,ISNULL(CHARINDEX(@separator, @valueList) + 1, 1),LEN(@valueList)))));

		-- INSERT currLDUN and currSID
		INSERT INTO @result
		SELECT @rowKey, @currRowValue;

		SET @Count = @Count - 1;		-- DECREASE COUNT
		SET @currRowValue = NULL					-- RESET SID VARIABLE
	END;
END;

-- RESET PROCESS VARIABLES:
	SET	@Count = NULL;

-- SHOW USER END RESULT:
return
end
GO


