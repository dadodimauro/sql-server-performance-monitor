use [awr_test]
go

------------------------------------------------------------------------------------------------------
-- CREATE A LOGGING PRCEDURE USED TO RETREIVE DATA AND STORE IT IN THE PREVIOUSLY CREATED TABLES
------------------------------------------------------------------------------------------------------
if not exists (select * from information_schema.routines where routine_name = 'sp_sql_perf_mon_logger')
	exec ('create proc [dbo].[sp_sql_perf_mon_logger] as select ''sp_sql_perf_mon_logger placeholder''')
go

alter procedure [dbo].[sp_sql_perf_mon_logger]
as

set nocount on;
set transaction isolation level read uncommitted;

declare	@product_version nvarchar(128)
declare @product_version_major decimal(10,2)
declare @product_version_minor decimal(10,2)
declare	@sql_memory_mb int
declare @os_memory_mb int
declare @memory_available int
declare @percent_idle_time real
declare @percent_processor_time real
declare @date_snapshot_current datetime
declare @date_snapshot_previous datetime
declare @sp_whoisactive_destination_table varchar(255)

declare @sql nvarchar(4000)

--------------------------------------------------------------------------------------------------------------
-- detect which version of sql we are running as some dmvs are different in different versions of sql
--------------------------------------------------------------------------------------------------------------
set @product_version = convert(nvarchar(128),serverproperty('productversioN'));

select
		@product_version_major = substring(@product_version, 1,charindex('.', @product_version) + 1 )
	,@product_version_minor = parsename(convert(varchar(32), @product_version), 2);

--------------------------------------------------------------------------------------------------------------
-- get available memory on the server
--------------------------------------------------------------------------------------------------------------
select @sql_memory_mb = convert(int,value) from sys.configurations where name = 'max server memory (mb)'

if @product_version_major < 11
	begin
		--sql < 2012
		exec sp_executesql N'select @osmemorymb=physical_memory_in_bytes/1024/1024  from sys.dm_os_sys_info', N'@osmemorymb int out', @os_memory_mb out
	end
else
	begin
		exec sp_executesql N'select @osmemorymb=physical_memory_kb/1024 from sys.dm_os_sys_info', N'@osmemorymb int out', @os_memory_mb out
	end

select @memory_available=min(memory_available) from (
	select memory_available=@sql_memory_mb
	union all
	select memory_available=@sql_memory_mb
) m

--------------------------------------------------------------------------------------------------------------
-- set the basics
--------------------------------------------------------------------------------------------------------------
select @date_snapshot_previous = max([snapshot_time])
from [dbo].[sql_perf_mon_snapshot_header]

set @date_snapshot_current = getdate();
insert into [dbo].[sql_perf_mon_snapshot_header]
values (@date_snapshot_current)


--------------------------------------------------------------------------------------------------------------
-- 1. get cpu
--------------------------------------------------------------------------------------------------------------
select
		@percent_processor_time=processutilization
	,	@percent_idle_time=systemidle
FROM (
		SELECT SystemIdle=record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'),
			ProcessUtilization=record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
		FROM (
			SELECT TOP 1 CONVERT(xml, record) AS [record]
			FROM sys.dm_os_ring_buffers WITH (NOLOCK)
			WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
			AND record LIKE N'%<SystemHealth>%'
			ORDER BY [timestamp] DESC
			) AS x
		) AS y
OPTION (RECOMPILE);

--------------------------------------------------------------------------------------------------------------
-- 2. get perfomance counters
-- this is where it gets interesting. there are several types of performance counters identified by the cntr_type
-- depending on the type, we may have to calculate deltas or deviation from the base.

-- cntr_type description from:
--	https://blogs.msdn.microsoft.com/psssql/2013/09/23/interpreting-the-counter-values-from-sys-dm_os_performance_counters/
--  https://rtpsqlguy.wordpress.com/2009/08/11/sys-dm_os_performance_counters-explained/

-- 65792 -> this counter value shows the last observed value directly. no calculation required.
-- 537003264 and 1073939712 -> this is similar to the above 65792 but we must divide the results by the base
--------------------------------------------------------------------------------------------------------------

insert into dbo.sql_perf_mon_perf_counters
select
		pc.[object_name]
	,pc.instance_name
	,pc.counter_name
	,pc.cntr_value
	,base_cntr_value=bc.cntr_value
	,pc.cntr_type
	,snapshot_time=@date_snapshot_current
from (
	select * from sys.dm_os_performance_counters
	union all
	/*  becuase we are only querying sql related performance counters (as only those are exposed through sql) we do not
		capture os performance counters such as cpu - hence we captured cpu from ringbuffer and now are going to
		make them look like real counter (othwerwise i would have to make up a name) */
	select
			[object_name] = 'win32_perfformatteddata_perfos_processor'
		,[counter_name] = 'Processor Time %'
		,[instance_name] = 'sql'
		,[cntr_value] = @percent_processor_time
		,[cntr_type] = 65792
	union all
	select
			[object_name] = 'win32_perfformatteddata_perfos_processor'
		,[counter_name] = 'Idle Time %'
		,[instance_name] = '_total'
		,[cntr_value] = @percent_idle_time
		,[cntr_type] = 65792
	union all
	select
			[object_name] = 'win32_perfformatteddata_perfos_processor'
		,[counter_name] = 'Processor Time %'
		,[instance_name] = 'system'
		,[cntr_value] = (100-@percent_idle_time-@percent_processor_time)
		,[cntr_type] = 65792
	) pc
inner join dbo.sql_perf_mon_config_perf_counters sc
on rtrim(pc.[object_name]) like '%' + sc.[object_name]
	and pc.counter_name = sc.counter_name
	and (
		rtrim(pc.instance_name) = sc.instance_name
		or	(
			sc.instance_name = '<* !_total>'
			and rtrim(pc.instance_name) <> '_total'
			)
		)
	outer apply (
				select pc2.cntr_value
				from sys.dm_os_performance_counters as pc2
				where pc2.cntr_type = 1073939712
					and pc2.[object_name] = pc.[object_name]
					and pc2.instance_name = pc.instance_name
					and rtrim(pc2.counter_name) = sc.base_counter_name
				) bc
where sc.collect = 1
option (recompile)

--------------------------------------------------------------------------------------------------------------
-- get process memory
--------------------------------------------------------------------------------------------------------------
insert into dbo.sql_perf_mon_os_process_memory
select snapshot_time=@date_snapshot_current, *
from sys.dm_os_process_memory

--------------------------------------------------------------------------------------------------------------
-- get sql memory. dynamic again based on sql version
--------------------------------------------------------------------------------------------------------------
declare @dm_os_memory_clerks table (
	[type] varchar(60),
	memory_node_id smallint,
	single_pages_kb bigint,
	multi_pages_kb bigint,
	virtual_memory_reserved_kb bigint,
	virtual_memory_committed_kb bigint,
	awe_allocated_kb bigint,
	shared_memory_reserved_kb bigint,
	shared_memory_committed_kb bigint
)
if @product_version_major < 11
	begin
		insert into @dm_os_memory_clerks
		exec sp_executesql N'
		select
			type,
			memory_node_id as memory_node_id,
			-- see comment in the sys.dm_os_memory_nodes query (above) for more info on
			-- [single_pages_kb] and [multi_pages_kb].
			sum(single_pages_kb) as single_pages_kb,
			0 as multi_pages_kb,
			sum(virtual_memory_reserved_kb) as virtual_memory_reserved_kb,
			sum(virtual_memory_committed_kb) as virtual_memory_committed_kb,
			sum(awe_allocated_kb) as awe_allocated_kb,
			sum(shared_memory_reserved_kb) as shared_memory_reserved_kb,
			sum(shared_memory_committed_kb) as shared_memory_committed_kb
		from sys.dm_os_memory_clerks
		group by type, memory_node_id
		option (recompile)
		'
	end
else
	begin
		insert into @dm_os_memory_clerks
		exec sp_executesql N'
		select
			type,
			memory_node_id as memory_node_id,
			-- see comment in the sys.dm_os_memory_nodes query (above) for more info on
			-- [single_pages_kb] and [multi_pages_kb].
			sum(pages_kb) as single_pages_kb,
			0 as multi_pages_kb,
			sum(virtual_memory_reserved_kb) as virtual_memory_reserved_kb,
			sum(virtual_memory_committed_kb) as virtual_memory_committed_kb,
			sum(awe_allocated_kb) as awe_allocated_kb,
			sum(shared_memory_reserved_kb) as shared_memory_reserved_kb,
			sum(shared_memory_committed_kb) as shared_memory_committed_kb
		from sys.dm_os_memory_clerks
		group by type, memory_node_id
		option (recompile)
	'
	end

declare @memory_clerks table (
	[type] varchar(60),
	memory_node_id smallint,
	single_pages_kb bigint,
	multi_pages_kb bigint,
	virtual_memory_reserved_kb bigint,
	virtual_memory_committed_kb bigint,
	awe_allocated_kb bigint,
	shared_memory_reserved_kb bigint,
	shared_memory_committed_kb bigint,
	snapshot_time datetime,
	total_kb bigint
)
insert into @memory_clerks
select
	mc.[type], mc.memory_node_id, mc.single_pages_kb, mc.multi_pages_kb, mc.virtual_memory_reserved_kb,
	mc.virtual_memory_committed_kb, mc.awe_allocated_kb, mc.shared_memory_reserved_kb, mc.shared_memory_committed_kb,
	snapshot_time = @date_snapshot_current,
	cast (mc.single_pages_kb as bigint)
		+ mc.multi_pages_kb
		+ (case when type <> 'MEMORYCLERK_SQLBUFFERPOOL' then mc.virtual_memory_committed_kb else 0 end)
		+ mc.shared_memory_committed_kb as total_kb
from @dm_os_memory_clerks as mc

insert into dbo.sql_perf_mon_os_memory_clerks
select
	snapshot_time =@date_snapshot_current,
	total_kb=sum(mc.total_kb),
	allocated_kb=sum(mc.single_pages_kb + mc.multi_pages_kb),
	--ta.total_kb_all_clerks,
	--mc.total_kb / convert(decimal, ta.total_kb_all_clerks) as percent_total_kb,
	sum(ta.total_kb_all_clerks) as total_kb_all_clerks,
	-- there are many memory clerks. we'll chart any that make up 5% of sql memory or more; less significant clerks will be lumped into an "other" bucket
	graph_type=case when mc.total_kb / convert(decimal, ta.total_kb_all_clerks) > 0.05 then mc.[type] else N'other' end
	,memory_available=@memory_available
from @memory_clerks as mc
-- use a self-join to calculate the total memory allocated for each time interval
join
(
	select
		snapshot_time = @date_snapshot_current,
		sum (mc_ta.total_kb) as total_kb_all_clerks
	from @memory_clerks as mc_ta
	group by mc_ta.snapshot_time
) as ta on (mc.snapshot_time = ta.snapshot_time)
group by mc.snapshot_time, case when mc.total_kb / convert(decimal, ta.total_kb_all_clerks) > 0.05 then mc.[type] else N'other' end
--order by snapshot_time
option (recompile)

delete from @memory_clerks


--------------------------------------------------------------------------------------------------------------
-- file stats snapshot
--------------------------------------------------------------------------------------------------------------
insert into dbo.sql_perf_mon_file_stats
select
	db_name (f.database_id) as [database_name], f.name as logical_file_name, f.type_desc,
	cast (case
	when left (ltrim (f.physical_name), 2) = '\\'
			then left (ltrim (f.physical_name), charindex ('\', ltrim (f.physical_name), charindex ('\', ltrim (f.physical_name), 3) + 1) - 1)
		when charindex ('\', ltrim(f.physical_name), 3) > 0
			then upper (left (ltrim (f.physical_name), charindex ('\', ltrim (f.physical_name), 3) - 1))
		else f.physical_name
	end as varchar(255)) as logical_disk,
	fs.num_of_reads, fs.num_of_bytes_read, fs.io_stall_read_ms, fs.num_of_writes, fs.num_of_bytes_written,
	fs.io_stall_write_ms, fs.size_on_disk_bytes,
	snapshot_time=@date_snapshot_current
from sys.dm_io_virtual_file_stats (default, default) as fs
inner join sys.master_files as f on fs.database_id = f.database_id and fs.[file_id] = f.[file_id]

--------------------------------------------------------------------------------------------------------------
-- wait stats snapshot
--------------------------------------------------------------------------------------------------------------
insert into [dbo].[sql_perf_mon_wait_stats]
select [wait_type], [waiting_tasks_count], [wait_time_ms],[max_wait_time_ms], [signal_wait_time_ms], [snapshot_time]=@date_snapshot_current
from sys.dm_os_wait_stats;

/*
--------------------------------------------------------------------------------------------------------------
-- sp_whoisactive
-- Please download and install The Great sp_whoisactive from http://whoisactive.com/ and thank Adam Machanic
-- for the numerous times sp_whoisactive saved our backs.

-- an alternative approach would be to use the SQL deadlock monitor and service broker to record blocking
-- or deadlocked transactions into a table -- or XE to save to xml - but this could cause trouble parsing large
-- xmls.
--------------------------------------------------------------------------------------------------------------
if object_id('master.dbo.sp_whoisactive') is not null
	begin
		truncate table [dbo].[sql_perf_mon_who_is_active_tmp]
		-- we are running WhoIsActive is very lightweight mode without any additional info and without execution plans
		set @sp_whoisactive_destination_table = quotename(db_name()) + '.[dbo].[sql_perf_mon_who_is_active_tmp]'
		exec dbo.sp_whoisactive
			@get_outer_command = 1
			,@output_column_list = '[collection_time][start_time][session_id][status][percent_complete][host_name][database_name][program_name][sql_text][sql_command][login_name][open_tran_count][wait_info][blocking_session_id][blocked_session_count][CPU][used_memory][tempdb_current][tempdb_allocations][reads][writes][physical_reads][login_time]'
			,@find_block_leaders = 1
			,@destination_table = @sp_whoisactive_destination_table

		-- the insert to tmp then actual table approach is required mainly to use our
		-- snapshot_time and enforce referential integrity with the header table and
		-- to apply any additional filtering:
		insert into [dbo].[sql_perf_mon_who_is_active]
		select   [snapshot_time] = @date_snapshot_current
				,[start_time],[session_id],[status],[percent_complete],[host_name]
				,[database_name],[program_name],[sql_text],[sql_command],[login_name]
				,[open_tran_count],[wait_info],[blocking_session_id],[blocked_session_count]
				,[CPU],[used_memory],[tempdb_current],[tempdb_allocations],[reads]
				,[writes],[physical_reads],[login_time]
		from [dbo].[sql_perf_mon_who_is_active_tmp]
		-- exclude anything that has been running for less that the desired age in seconds (default 60)
		-- this parameterised so feel free to change it to your liking. To change parameter:
		-- update [dbo].[sql_perf_mon_config_who_is_active_age] set [seconds] = x
		where [start_time] < dateadd(s,(select [seconds]*-1.0 from [dbo].[sql_perf_mon_config_who_is_active_age]),getdate())
		-- unless its being blocked or is a blocker
		or [blocking_session_id] is not null or [blocked_session_count] > 0
	end
else
	begin
		print 'sp_WhoIsActive not found.'
	end
go
*/
GO

----------------------------------------------------------------------------------------
-- RETENTION PROCEDURE
-- By default, the retention is scheduled to 7 rolling days and its best to run the
-- retention job often to delete small chunks of data rather than one big run once
-- a week which, due to cascade delete can blow transaction log
----------------------------------------------------------------------------------------
if not exists (select * from information_schema.routines where routine_name = 'sp_sql_perf_mon_retention')
exec ('create proc [dbo].[sp_sql_perf_mon_retention] as select ''sp_sql_perf_mon_retention placeholder''')
go

alter procedure [dbo].[sp_sql_perf_mon_retention] (
	@retention_period_days smallint = 7,
	@batch_size smallint = 500  -- max element dele
	)
as
set nocount on;
declare @row_count int = 1

while @row_count > 0
	begin
		begin tran
		delete top (@batch_size)
		from dbo.sql_perf_mon_snapshot_header with (readpast)
		where datediff(day,snapshot_time,getdate()) > @retention_period_days  -- delete all entries older
																			  -- the @retention_period_days
		set @row_count = @@ROWCOUNT
		commit tran
	end
go

if @@trancount > 0
	commit
