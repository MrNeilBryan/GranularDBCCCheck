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
  1. Ensure that there is a SQLAdministration database to work in. Otherwise change the USE command in each script to reflect the database that will be used.
  2. Run the attached scripts in order in the target database (e.g. SQLAdministration).
  

Summary 
By implementing this new job, we aim to improve the efficiency and reliability of our database integrity checks. If successful, we will consider rolling out this approach across the entire estate. 
