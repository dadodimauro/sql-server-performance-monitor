# .\export_data.ps1 -filepath "C:\Users\Administrator\Documents\output\"
param
	(
		[string]$outputType="text",
		[string]$filepath,
		[string]$aggregation="60"
	)

function ExportViewTolFile ([string]$filename, [string]$query)

{
	#Connection to SQL Server and DB
	$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
	$SqlConnection.ConnectionString = "Server=localhost\MSSQLA01;Integrated Security=True;Initial Catalog=master"
	$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
	#Connection to query
	$SqlCmd.CommandText = $query
	#SQL Connection by SQL ADAPTER
	$SqlCmd.Connection = $SqlConnection
	$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$SqlAdapter.SelectCommand = $SqlCmd
	#SQL Dataset
	$DataSet = New-Object System.Data.DataSet
	$SqlAdapter.Fill($DataSet)
	$SqlConnection.Close()

	$fullpath = $filepath + $filename
	$fullpath

	if ($outputType -eq "text")
	{
		$DataSet.Tables[0] | export-csv -Path $fullpath -NoTypeInformation #export in format CSV
	}
	if ($outputType -eq "xml")
	{
		$DataSet.Tables[0] | Export-Clixml -Path $fullpath -NoTypeInformation #export in format XML
	}
}
# memory query
"executing memory query..."
$query = "use [awr_test]

			DECLARE @aggregation_time int
			SET @aggregation_time = AGGREGATION_TIME

			SELECT [report_name]
				 ,DATEADD(minute,
							(DATEDIFF(minute, 0, [report_time]) / @aggregation_time) * @aggregation_time,
							0) AS [report_time]
				 ,avg([Physical memory in use (MB)]) as [Physical memory in use (MB)]
				 ,avg([Locked page allocations (MB)]) as [Locked page allocations (MB)]
				 ,avg([Page faults]) as [Page faults]
				 ,avg([Memory utilisation %]) as [Memory utilisation %]
				 ,avg([report_time_interval_minutes]) as [report_time_interval_minutes]
			  FROM [awr_test].[dbo].[vw_sql_perf_mon_rep_mem_proc]
			  GROUP BY DATEADD(minute,
							(DATEDIFF(minute, 0, [report_time]) / @aggregation_time) * @aggregation_time,
							0), [report_name]
			  ORDER BY [report_time]
"
$query = $query.replace('AGGREGATION_TIME', $aggregation)
ExportViewTolFile -filename "memory.csv" -query $query
"memory query complete!"

# performance counters query
"executing performance_counters query..."
$query = "use [awr_test]

			DECLARE @aggregation_time int
			SET @aggregation_time = AGGREGATION_TIME

			SELECT [report_name]
				  ,DATEADD(minute,
							(DATEDIFF(minute, 0, [report_time]) / @aggregation_time) * @aggregation_time,
							0) AS [report_time]
				  ,[object_name]
				  ,[instance_name]
				  ,[counter_name]
				  ,avg([cntr_value]) as [cntr_value]
				  ,avg([report_time_interval_minutes]) as [report_time_interval_minutes]
			FROM [awr_test].[dbo].[vw_sql_perf_mon_rep_perf_counter]
			GROUP BY DATEADD(minute,
							(DATEDIFF(minute, 0, [report_time]) / @aggregation_time) * @aggregation_time,
							0), [report_name], [object_name], [instance_name], [counter_name]
			ORDER BY [report_time]
"
$query = $query.replace('AGGREGATION_TIME', $aggregation)
ExportViewTolFile -filename "performance_counters.csv" -query $query
"performance_counters query complete!"

# waits query
"executing waits query..."
$query = "use [awr_test]

			DECLARE @aggregation_time int
			SET @aggregation_time = AGGREGATION_TIME

			SELECT [wait_type]
					,[category_name]
					,[ignore]
					,DATEADD(minute,
							(DATEDIFF(minute, 0, [snapshot_time]) / @aggregation_time) * @aggregation_time,
							0) AS [report_time]
					,avg([waiting_tasks_count]) as [waiting_tasks_count]
					,avg([wait_time_ms]) as [wait_time_ms]
					,avg([max_wait_time_ms]) as [max_wait_time_ms]
					,avg([signal_wait_time_ms]) as [signal_wait_time_ms]
			FROM [awr_test].[dbo].[vw_sql_perf_mon_wait_stats_categorised]
			GROUP BY DATEADD(minute,
							(DATEDIFF(minute, 0, [snapshot_time]) / @aggregation_time) * @aggregation_time,
							0), [wait_type], [category_name], [ignore]
			ORDER BY [report_time]
"
$query = $query.replace('AGGREGATION_TIME', $aggregation)
ExportViewTolFile -filename "waits.csv" -query $query
"waits query complete!"

# all snapshots query
"executing snapshots queries..."
$query = "use [awr_test]

			SELECT [spapshot_interval_start]
				  ,[snapshot_interval_end]
				  ,[first_snapshot_time]
				  ,[last_snapshot_time]
				  ,[snapshot_age_hours]
				  ,[report_time_interval_minutes]
			FROM [awr_test].[dbo].[vw_sql_perf_mon_time_intervals]
			ORDER BY [spapshot_interval_start]
"
ExportViewTolFile -filename "all_snapshots.csv" -query $query

# snapshots query
$query = "use [awr_test]

			DECLARE @aggregation_time int
			SET @aggregation_time = AGGREGATION_TIME

			SELECT DATEADD(minute,
							(DATEDIFF(minute, 0, [spapshot_interval_start]) / @aggregation_time) * @aggregation_time,
							0) AS [report_time]
			FROM [awr_test].[dbo].[vw_sql_perf_mon_time_intervals]
			GROUP BY DATEADD(minute,
							(DATEDIFF(minute, 0, [spapshot_interval_start]) / @aggregation_time) * @aggregation_time,
							0)
			ORDER BY [report_time]
"
$query = $query.replace('AGGREGATION_TIME', $aggregation)
ExportViewTolFile -filename "snapshots.csv" -query $query
"snapshots queries complete!"
