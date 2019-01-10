# SQL Scripts
### by Deep Jyoti

Repository of useful generic scripts and constructs that can be used for any MSSQL database.

### UNIQUE INDEX AS UNIQUE OR NULL CONSTRAINT

In SQL Server, UNIQUE Constraints do not allow for multiple NULLs. To create a constraint that allows for this behavior, we actually have to create a unique index:

CREATE UNIQUE INDEX index_name ON schema.table(target_column) WHERE target_column IS NOT NULL;
