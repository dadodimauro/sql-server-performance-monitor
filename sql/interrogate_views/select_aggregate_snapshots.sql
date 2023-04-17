use [awr_test]

DECLARE @aggregation_time int
SET @aggregation_time = 60

SELECT DATEADD(minute,
				(DATEDIFF(minute, 0, [spapshot_interval_start]) / @aggregation_time) * @aggregation_time,
				0) AS [report_time]
FROM [awr_test].[dbo].[vw_sql_perf_mon_time_intervals]
GROUP BY DATEADD(minute,
				(DATEDIFF(minute, 0, [spapshot_interval_start]) / @aggregation_time) * @aggregation_time,
				0)
ORDER BY [report_time]