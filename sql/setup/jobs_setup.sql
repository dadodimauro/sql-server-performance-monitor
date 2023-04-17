------------------------------------------------------------------------------------------------------------------------------
-- setup jobs
-- https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-add-jobschedule-transact-sql?view=sql-server-ver16
-- we have to switch database to msdb but we also need to know which db jobs should run in so have to capture current database:
------------------------------------------------------------------------------------------------------------------------------

declare @database varchar(255)
declare @server nvarchar(255)
set @database = DB_NAME()
set @server = @@SERVERNAME

USE [msdb]

DECLARE @jobId BINARY(16)
DECLARE @schedule_id int;


-- LOGGER JOB
if (select name from sysjobs where name = 'DBA-PERF-LOGGER') is null
	begin
		EXEC  msdb.dbo.sp_add_job @job_name=N'DBA-PERF-LOGGER',
				@enabled=1,
				@notify_level_eventlog=0,
				@notify_level_email=2,
				@notify_level_page=2,
				@delete_level=0,
				@category_name=N'Data Collector',
				@owner_login_name=N'sa', @job_id = @jobId OUTPUT;

		EXEC msdb.dbo.sp_add_jobserver @job_name=N'DBA-PERF-LOGGER', @server_name = @server;

		EXEC msdb.dbo.sp_add_jobstep @job_name=N'DBA-PERF-LOGGER', @step_name=N'DBA-PERF-LOGGER',
				@step_id=1,
				@cmdexec_success_code=0,
				@on_success_action=1,
				@on_fail_action=2,
				@retry_attempts=0,
				@retry_interval=0,
				@os_run_priority=0, @subsystem=N'TSQL',
				@command=N'exec [dbo].[sp_sql_perf_mon_logger]',  -- exec this procedure
				@database_name=@database,
				@flags=0;

		EXEC msdb.dbo.sp_update_job @job_name=N'DBA-PERF-LOGGER',
				@enabled=1,
				@start_step_id=1,
				@notify_level_eventlog=0,
				@notify_level_email=2,
				@notify_level_page=2,
				@delete_level=0,
				@description=N'',
				@category_name=N'Data Collector',
				@owner_login_name=N'sa',
				@notify_email_operator_name=N'',
				@notify_page_operator_name=N'';

		EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DBA-PERF-LOGGER', @name=N'DBA-PERF-LOGGER',
				@enabled=1,
				@freq_type=4,  -- daily
				@freq_interval=1,  -- once
				@freq_subday_type=4,  -- minute interval
				@freq_subday_interval=1, -- exec every 1 minute
				@freq_relative_interval=0,
				@freq_recurrence_factor=1,
				@active_start_date=20180804,
				@active_end_date=99991231,
				@active_start_time=12,
				@active_end_time=235959, @schedule_id = @schedule_id OUTPUT;
	end


-- RETENTION JOB
if (select name from sysjobs where name = 'DBA-PERF-LOGGER-RETENTION') is  null
	begin
		set @jobId = null
		EXEC  msdb.dbo.sp_add_job @job_name=N'DBA-PERF-LOGGER-RETENTION',
				@enabled=1,
				@notify_level_eventlog=0,
				@notify_level_email=2,
				@notify_level_page=2,
				@delete_level=0,
				@category_name=N'Data Collector',
				@owner_login_name=N'sa', @job_id = @jobId OUTPUT;

		EXEC msdb.dbo.sp_add_jobserver @job_name=N'DBA-PERF-LOGGER-RETENTION', @server_name = @server;

		EXEC msdb.dbo.sp_add_jobstep @job_name=N'DBA-PERF-LOGGER-RETENTION', @step_name=N'DBA-PERF-LOGGER-RETENTION',
				@step_id=1,
				@cmdexec_success_code=0,
				@on_success_action=1,
				@on_fail_action=2,
				@retry_attempts=0,
				@retry_interval=0,
				@os_run_priority=0, @subsystem=N'TSQL',
				@command=N'exec dbo.sp_sql_perf_mon_retention',
				@database_name=@database,
				@flags=0;

		EXEC msdb.dbo.sp_update_job @job_name=N'DBA-PERF-LOGGER-RETENTION',
				@enabled=1,
				@start_step_id=1,
				@notify_level_eventlog=0,
				@notify_level_email=2,
				@notify_level_page=2,
				@delete_level=0,
				@description=N'',
				@category_name=N'Data Collector',
				@owner_login_name=N'sa',
				@notify_email_operator_name=N'',
				@notify_page_operator_name=N'';

		set @schedule_id = null
		EXEC msdb.dbo.sp_add_jobschedule @job_name=N'DBA-PERF-LOGGER-RETENTION', @name=N'DBA-PERF-LOGGER-RETENTION',
				@enabled=1,
				@freq_type=4,  -- daily
				@freq_interval=1,  -- once a day
				@freq_subday_type=8,  -- hours
				@freq_subday_interval=1, -- each hour (is better to do it frequently because of the DELETE CASCADE
				@freq_relative_interval=0,
				@freq_recurrence_factor=1,
				@active_start_date=20180804,
				@active_end_date=99991231,
				@active_start_time=20,
				@active_end_time=235959, @schedule_id = @schedule_id OUTPUT
	end

if @@trancount > 0
	commit