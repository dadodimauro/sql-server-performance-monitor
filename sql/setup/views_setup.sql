use [awr_test]
go

--------------------------------------------------------------------------------------------------------------
-- get process memory. table layout differes between different sql versions so we will take
-- dynamic approach and create table if it does not exists straight from results (select into)
--------------------------------------------------------------------------------------------------------------

-- PROCESS MEMORY
declare @sql nvarchar(4000)
if object_id('[dbo].[sql_perf_mon_os_process_memory]') is null
	begin
		set @sql = 'select snapshot_time=convert(datetime,''' + convert(varchar(23),GETDATE(),121) + '''), * into dbo.sql_perf_mon_os_process_memory from sys.dm_os_process_memory where 1=2'
		exec sp_executesql @sql
		alter table [dbo].[sql_perf_mon_os_process_memory] alter column [snapshot_time] datetime not null
		alter table [dbo].[sql_perf_mon_os_process_memory] add primary key ([snapshot_time])

		alter table [dbo].[sql_perf_mon_os_process_memory] add constraint fk_sql_perf_mon_os_process_memory foreign key ([snapshot_time])
		references	[dbo].[sql_perf_mon_snapshot_header] ([snapshot_time])
		on delete cascade
	end
go

-- porcess memory view
if object_id('[dbo].[vw_sql_perf_mon_rep_mem_proc]') is null
	exec ('create view [dbo].[vw_sql_perf_mon_rep_mem_proc] as select dummy=''placeholder''')
go

alter view [dbo].[vw_sql_perf_mon_rep_mem_proc] as
	select
		 [report_name] = 'process memory'
		,[report_time] = s.[snapshot_interval_end]
		,[Physical memory in use (MB)]=avg([physical_memory_in_use_kb]/1024)
		,[Locked page allocations (MB)]=avg([locked_page_allocations_kb]/1024)
		,[Page faults]=avg([page_fault_count])
		,[Memory utilisation %]=avg([memory_utilization_percentage])
		,s.[report_time_interval_minutes]
	from [dbo].[sql_perf_mon_os_process_memory]  pm
	inner join [dbo].[vw_sql_perf_mon_time_intervals] s
		on pm.snapshot_time >= s.first_snapshot_time
		and pm.snapshot_time <= s.last_snapshot_time
	group by s.[snapshot_interval_end],s.[report_time_interval_minutes]
go

-------------------------------------------------------------------------------------------------------------
-- performance metrics view
-- THIS IS COMPLICATED
-- 65792 -> this counter value shows the last observed value directly. no calculation required.
-- 537003264 and 1073939712 -> this is similar to the above 65792 but we must divide the results by the base
-- so a different approach is needed to compute each values
-- MORE INFO IN THE LOGGING PROCEDURE
-------------------------------------------------------------------------------------------------------------
if object_id('[dbo].[vw_sql_perf_mon_rep_perf_counter]') is null
	exec ('create view [dbo].[vw_sql_perf_mon_rep_perf_counter] as select dummy=''placeholder''')
go

alter view [dbo].[vw_sql_perf_mon_rep_perf_counter] as
			select distinct
				 [report_name] = 'Performance Counters'
				,[report_time] = s.snapshot_interval_end
				,[object_name] = rtrim(ltrim(pc.[object_name]))
				,[instance_name] = rtrim(ltrim(isnull(pc.instance_name, '')))
				,counter_name = rtrim(ltrim(pc.counter_name))
				,[cntr_value] = convert(real,(
					case
						when sc.object_name = 'Batch Resp Statistics' then case when pc.cntr_value > fsc.cntr_value then cast((pc.cntr_value - fsc.cntr_value) as real) else 0 end -- delta absolute
						when pc.cntr_type = 65792 then isnull(pc.cntr_value,0) -- point-in-time
						when pc.cntr_type = 272696576 then case when (pc.cntr_value > fsc.cntr_value) then (pc.cntr_value - fsc.cntr_value) / cast(datediff(second,s.first_snapshot_time,s.last_snapshot_time) as real) else 0 end -- delta rate
						when pc.cntr_type = 537003264 then isnull(cast(100.0 as real) * pc.cntr_value / nullif(bc.cntr_value, 0),0) -- ratio
						when pc.cntr_type = 1073874176 then isnull(case when pc.cntr_value > fsc.cntr_value then isnull((pc.cntr_value - fsc.cntr_value) / nullif(bc.cntr_value - fsc.base_cntr_value, 0) / cast(datediff(second,s.first_snapshot_time,s.last_snapshot_time) as real), 0) else 0 end,0) -- delta ratio
						end))
				,s.[report_time_interval_minutes]
		from dbo.sql_perf_mon_perf_counters as pc
		inner join [dbo].[vw_sql_perf_mon_time_intervals] s
			on pc.snapshot_time = s.last_snapshot_time

		inner join dbo.sql_perf_mon_config_perf_counters as sc
		on rtrim(pc.object_name) like '%' + sc.object_name
			and rtrim(pc.counter_name) = sc.counter_name
			and (rtrim(pc.instance_name) = sc.instance_name
				or (
					sc.instance_name = '<* !_total>'
					and rtrim(pc.instance_name) <> '_total'
					)
			)
		outer apply (
					select top (1) fsc.cntr_value,
									fsc.base_cntr_value
					from (
						select *
						from [dbo].[sql_perf_mon_perf_counters]
						where snapshot_time = s.first_snapshot_time
						) as fsc
					where fsc.[object_name] = rtrim(pc.[object_name])
							and fsc.counter_name = rtrim(pc.counter_name)
							and fsc.instance_name = rtrim(pc.instance_name)
					) as fsc
		outer apply (
					select top (1) pc2.cntr_value
					from [dbo].[sql_perf_mon_perf_counters] as pc2
					where snapshot_time = s.last_snapshot_time
						and pc2.cntr_type = 1073939712
							and pc2.object_name = pc.object_name
							and pc2.instance_name = pc.instance_name
							and rtrim(pc2.counter_name) = sc.base_counter_name
					) as bc
		where -- exclude base counters
				pc.cntr_type in (65792,272696576,537003264,1073874176)
go

if @@trancount > 0
	commit





