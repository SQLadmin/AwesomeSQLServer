/********************************************************************************************

***  Session Momitoring using sp_whoisactive ***
------------------------------------------------

I have prepared this script to monitor currently running sessions
in different scenarios like CPU, Blocking, So first you need to
create sp_whoisactive stored procedure, please downad it from the link,

https://github.com/SqlAdmin/AwesomeSQLServer/blob/master/T-SQL%20Scripts/sp_whoisactive.sql

*******************************************************************************************/ 


-- To get overall info about current sessions

EXEC sp_whoisactive


------------------------------------------------
/*** 1. Currently running sessions CPU time ***/
------------------------------------------------

EXEC sp_WhoIsActive @get_plans = 1,
                    @get_avg_time = 1,
                    @output_column_list = '[dd%][session_id][database_name][cpu%][sql_text]',
                    @sort_order = '[start_time] ASC'


-----------------------------------------------------------
/*** 2. Currently running sessions memory pages usage ***/
-----------------------------------------------------------

EXEC sp_WhoIsActive @output_column_list = '[dd%][session_id][database_name][sql_text][used_memory][tempdb_allocations][tempdb_current]',
                    @sort_order = '[start_time] ASC';


--------------------------------------------------------------
/*** 3. Currently running query, batch and execution plan ***/
--------------------------------------------------------------                   

EXEC sp_WhoIsActive @get_full_inner_text = 1,
                    @get_plans = 1,
                    @get_outer_command = 1,
                    @output_column_list = '[dd%][session_id][database_name][sql_text][sql_command][query_plan]',
                    @sort_order = '[start_time] ASC';


-----------------------------------------------------------------
/*** 4. Monitor Transaction log writing process of a session ***/
----------------------------------------------------------------- 

EXEC sp_WhoIsActive @get_transaction_info = 1,
                    @output_column_list = '[dd%][session_id][database_name][tran_log_writes]',
                    @sort_order = '[start_time] ASC';

               