use [awr_test]

DECLARE @aggregation_time int
SET @aggregation_time = 60

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