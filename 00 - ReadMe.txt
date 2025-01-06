Introduction 
We have a new version of the DBCC CHECKDB job, named SQLAdministration - Granular Database Checks. The idea is that instead of running the DBCC CHECKDB at the database level, we run the component parts of the DBCC CHECK. This means that we can part process DBCC Checks on large databases and pick up from where we left off the next time that job runs. 
  
 Job Details 
	•	Job Name: SQLAdministration - Granular Database Checks 
	•	Server: PRFSQLSVR01C (initially) 
	•	Backup Schedule: Sundays at 2 PM (will vary per server) 


  
Key Features 
This job leverages the granular integrity check approach proposed by Eitan Blumin. For more details, you can refer to Eitan Blumin's article. 
The job performs the following checks: 
	•	DBCC CHECKALLOC per database 
	•	DBCC CHECKCATALOG per database 
	•	DBCC CHECKTABLE per table in each database 


  
Timeout and Continuation 
	•	Timeout: 3 hours (configurable) 
	•	If the job times out, it will resume from where it left off during the next run. 


  
Implementation Details 
	•	Procedure Used: Hellengren DBCC database integrity procedure 
	•	Wrapper Procedure: SQLAdministration.[dbo].[usp_DBCC_Checks] 
	•	Logging: Output is recorded in the SQLAdministration.[dbo].[CommandLog] table. 


  
Benefits 
This granular approach is particularly beneficial for large databases that struggle to complete integrity checks within a reasonable timeframe. For example: 
	•	Wolves: Databases like PresentationMaster often fail to complete checks due to their size. 
	•	Chatham: Standard integrity checks can take up to two days on some servers. 


Installation
To install the acripts in this repository:
  1. Ensure that there is a SQLAdministration database to work in. Otherwise change the USE command in each script to reflect 
     the database that will be used.

  2. Run the attached scripts in order in the target database (e.g. SQLAdministration).
	
	01 - CreateTable_CommandLog.sql -- Creates the dbo.CommandLog table (Hellengren table)
	02 - CreateSproc_CommandExecute.sql -- Hellengren script from his website.
	03 - CreateSproc_DatabaseIntegrityCheck.sql -- Hellengren script from his website.
	04 - CreateSproc_Find_Tables_That_Have_Not_Had_A_DBCC_CHECK_For_X_Days.sql -- Check for tables that have not had a 
                                 						      check table for more than x days, where
										      x is an input parameter.
                                                                                      An output parameter has been added which
										      will return the number of tables missing
										      a CHECKTABLE to the caller.
	05 - CreateSproc_usp_DBCC_Checks.sql  -- Run the DBCC Checks.
 


  3. Create A SQL Agent job    
    
        A. Called: 	SQLAdministration - Granular Database Checks
        B. Description: New DBCC CHECKDB Job which runs at the object level.
		     	It does DBCC CHECKALLOC, DBCC CHECKCATALOG, DBCC CHECKTABLE.
		     	It has a timeout and and will continue from where is left off.
	C. Step 1	Run in the target database (e.g. SQLAdministration).
			Named: Run DBCC Checks
                        With the command: SQLAdministration database EXEC [dbo].[usp_DBCC_Checks] @MinutesToRunFor  = 180; 
			NOTE: Set the 180 in the command to the amount of minutes you need, the above example is 180 mins.
	D. Schedules:	Set the schedules up as you see fit.


Summary 
By implementing this new job, we aim to improve the efficiency and reliability of our database integrity checks. If successful, we will consider rolling out this approach across the entire estate. 
