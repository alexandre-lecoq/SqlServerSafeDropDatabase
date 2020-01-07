
-- This is a test script for SafeDropDatabase procedure.

EXEC dbo.SafeDropDatabase @DatabaseName = 'xxxxxx';

ALTER DATABASE [DROP_xxxxxx] SET MULTI_USER;

ALTER DATABASE [DROP_xxxxxx] MODIFY NAME = [xxxxxx];
