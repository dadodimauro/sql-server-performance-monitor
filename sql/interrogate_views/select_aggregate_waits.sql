use [awr_test]

DECLARE @aggregation_time int
SET @aggregation_time = 60

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
