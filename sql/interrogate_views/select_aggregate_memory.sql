use [awr_test]

DECLARE @aggregation_time int
SET @aggregation_time = 60

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

