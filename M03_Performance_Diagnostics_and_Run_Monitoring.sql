USE olist_analytics;

-- =========================================================
-- 1. VERIFY STORED PROCEDURE REGISTRATION
-- =========================================================
-- Confirm that the data-quality procedure exists in the
-- intended database and inspect its registration details.

SHOW PROCEDURE STATUS
WHERE Db = 'olist_analytics'
  AND Name = 'sp_run_data_quality_checks';


-- =========================================================
-- 2. CHECK RECENT VALIDATION RUNS
-- =========================================================
-- Review the latest executions to confirm whether runs were
-- completed successfully or recorded as failed.

SELECT *
FROM dq_validation_runs
ORDER BY run_id DESC
LIMIT 5;


-- =========================================================
-- 3. VERIFY DATABASE CONNECTION AND MYSQL VERSION
-- =========================================================
-- Confirm the active database and identify the MySQL server
-- version for troubleshooting compatibility issues.

SELECT
    DATABASE() AS active_database,
    VERSION() AS mysql_version;


-- =========================================================
-- 4. RECHECK STORED PROCEDURE REGISTRATION
-- =========================================================
-- Repeat the procedure lookup to verify that it remains
-- registered in the expected database.

SHOW PROCEDURE STATUS
WHERE Db = 'olist_analytics'
  AND Name = 'sp_run_data_quality_checks';


-- =========================================================
-- 5. INSPECT VALIDATION RUN STATUS AND ERRORS
-- =========================================================
-- Display recent run timestamps, execution statuses, and
-- any error messages recorded by the validation framework.

SELECT
    run_id,
    run_status,
    started_at,
    completed_at,
    error_message
FROM dq_validation_runs
ORDER BY run_id DESC
LIMIT 5;


-- =========================================================
-- 6. INSPECT SERVER TIMEOUT AND EXECUTION SETTINGS
-- =========================================================
-- Check connection timeouts, network timeouts, and the
-- execution-time limit that may affect long-running queries.
-- A variable may be unavailable on some MySQL versions.

SHOW VARIABLES
WHERE Variable_name IN (
    'wait_timeout',
    'interactive_timeout',
    'net_read_timeout',
    'net_write_timeout',
    'max_execution_time'
);


-- =========================================================
-- 7. CHECK SERVER TIME AND MAXIMUM PACKET SIZE
-- =========================================================
-- Confirm the server's current time and inspect the global
-- maximum packet size configured for client/server communication.

SELECT NOW() AS server_time,
       @@GLOBAL.max_allowed_packet AS max_packet_size;


-- =========================================================
-- 8. CHECK BASIC SERVER ACTIVITY METRICS
-- =========================================================
-- Inspect server uptime, currently running threads, and
-- the cumulative slow-query counter.

SHOW GLOBAL STATUS
WHERE Variable_name IN (
    'Uptime',
    'Threads_running',
    'Slow_queries'
);


-- =========================================================
-- 9. INSPECT THE STORED PROCEDURE DEFINITION
-- =========================================================
-- Retrieve the procedure's creation statement to verify
-- its definition and inspect its current implementation.

SHOW CREATE PROCEDURE sp_run_data_quality_checks;


-- =========================================================
-- 10. INSPECT CURRENTLY CONNECTED SESSIONS AND QUERIES
-- =========================================================
-- Review active database connections and running statements.
-- This can help identify a query that is still executing
-- or a session that may be blocking other work.

SHOW FULL PROCESSLIST;


-- =========================================================
-- 11. RECHECK THE STORED PROCEDURE DEFINITION
-- =========================================================
-- Repeat the definition lookup for another inspection of
-- the stored procedure currently registered on the server.

SHOW CREATE PROCEDURE sp_run_data_quality_checks;


-- =========================================================
-- 12. COUNT RECORDED DATA-QUALITY RESULTS
-- =========================================================
-- Count all rule-result records currently stored in the
-- data-quality results table across all validation runs.

SELECT COUNT(*) AS results_recorded
FROM olist_analytics.dq_rule_results;