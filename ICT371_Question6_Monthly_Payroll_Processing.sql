
/* ============================================================
   ICT371 - QUESTION 6
   MONTHLY PAYROLL PROCESSING

   STUDENT NAME: Enter your full name
   STUDENT NUMBER: Enter your student number
   COURSE CODE: ICT371
   ASSIGNMENT: Question 6 - Monthly Payroll Processing

   ============================================================ */


-- ============================================================
-- 1. CLEAN UP PREVIOUS QUESTION 6 OBJECTS
-- ============================================================

DROP VIEW IF EXISTS v_payroll_report CASCADE;

DROP PROCEDURE IF EXISTS pr_process_payroll(DATE);

DROP FUNCTION IF EXISTS fn_net_pay(INTEGER);
DROP FUNCTION IF EXISTS fn_audit_salary_change();

DROP TABLE IF EXISTS salary_audit CASCADE;
DROP TABLE IF EXISTS payroll CASCADE;
DROP TABLE IF EXISTS employees CASCADE;


-- ============================================================
-- 2. CREATE EMPLOYEES TABLE
-- All money inputs must be non-negative.
-- ============================================================

CREATE TABLE employees (
    employee_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    basic_salary NUMERIC(12,2) NOT NULL CHECK (basic_salary >= 0),
    allowance NUMERIC(12,2) NOT NULL CHECK (allowance >= 0),
    deduction NUMERIC(12,2) NOT NULL CHECK (deduction >= 0),
    active BOOLEAN NOT NULL DEFAULT TRUE
);


-- ============================================================
-- 3. CREATE PAYROLL TABLE
-- Each employee can have only one record per month.
-- pay_month must be the first day of a month.
-- ============================================================

CREATE TABLE payroll (
    payroll_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
    pay_month DATE NOT NULL,
    gross_pay NUMERIC(12,2) NOT NULL CHECK (gross_pay >= 0),
    net_pay NUMERIC(12,2) NOT NULL CHECK (net_pay >= 0),

    CONSTRAINT uq_employee_pay_month
        UNIQUE (employee_id, pay_month),

    CONSTRAINT chk_pay_month_start
        CHECK (
            EXTRACT(DAY FROM pay_month) = 1
        )
);


-- ============================================================
-- 4. CREATE SALARY AUDIT TABLE
-- Records actual changes to basic salary.
-- ============================================================

CREATE TABLE salary_audit (
    audit_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
    old_salary NUMERIC(12,2) NOT NULL,
    new_salary NUMERIC(12,2) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ============================================================
-- 5. INSERT SAMPLE EMPLOYEES
-- Three active employees and one inactive employee.
-- ============================================================

INSERT INTO employees (
    full_name,
    basic_salary,
    allowance,
    deduction,
    active
)
VALUES
    ('John Banda', 5000.00, 500.00, 300.00, TRUE),
    ('Mary Phiri', 6000.00, 700.00, 500.00, TRUE),
    ('Peter Zulu', 4000.00, 300.00, 200.00, TRUE),
    ('Grace Tembo', 5500.00, 400.00, 250.00, FALSE);


-- ============================================================
-- 6. CREATE FUNCTION
-- fn_net_pay(p_employee_id)
-- Calculates current net pay:
-- basic salary + allowance - deduction.
-- Rejects unknown employees and negative net pay.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_net_pay(
    p_employee_id INTEGER
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_basic_salary NUMERIC(12,2);
    v_allowance NUMERIC(12,2);
    v_deduction NUMERIC(12,2);
    v_net_pay NUMERIC(12,2);
BEGIN

    SELECT
        basic_salary,
        allowance,
        deduction
    INTO
        v_basic_salary,
        v_allowance,
        v_deduction
    FROM employees
    WHERE employee_id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Unknown employee ID: %',
            p_employee_id;
    END IF;

    v_net_pay :=
        v_basic_salary + v_allowance - v_deduction;

    IF v_net_pay < 0 THEN
        RAISE EXCEPTION
            'Net pay cannot be negative for employee ID %',
            p_employee_id;
    END IF;

    RETURN v_net_pay;

END;
$$;


-- ============================================================
-- 7. CREATE TRIGGER FUNCTION
-- Records basic salary changes using OLD and NEW values.
-- No audit record is created when salary is unchanged.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_audit_salary_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN

        INSERT INTO salary_audit (
            employee_id,
            old_salary,
            new_salary,
            changed_at
        )
        VALUES (
            OLD.employee_id,
            OLD.basic_salary,
            NEW.basic_salary,
            CURRENT_TIMESTAMP
        );

    END IF;

    RETURN NEW;

END;
$$;


-- ============================================================
-- 8. CREATE AFTER UPDATE TRIGGER
-- ============================================================

CREATE TRIGGER trg_salary_change_audit
AFTER UPDATE
ON employees
FOR EACH ROW
EXECUTE FUNCTION fn_audit_salary_change();


-- ============================================================
-- 9. TEST THE SALARY AUDIT TRIGGER
-- Change John's basic salary from 5000 to 5100.
-- This should create one audit record.
-- ============================================================

UPDATE employees
SET basic_salary = 5100.00
WHERE employee_id = 1;


-- ============================================================
-- 10. CREATE PAYROLL PROCESSING PROCEDURE
-- Uses a FOR loop over active employees.
-- Inserts missing employee/month records only.
-- Existing payroll rows remain unchanged.
-- ============================================================

CREATE OR REPLACE PROCEDURE pr_process_payroll(
    p_month DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_employee RECORD;
    v_gross_pay NUMERIC(12,2);
    v_net_pay NUMERIC(12,2);
BEGIN

    -- Require a valid month-start date.

    IF p_month IS NULL THEN
        RAISE EXCEPTION
            'Payroll month cannot be NULL';
    END IF;

    IF EXTRACT(DAY FROM p_month) <> 1 THEN
        RAISE EXCEPTION
            'Payroll month must be the first day of a month';
    END IF;


    -- Loop through active employees only.

    FOR v_employee IN
        SELECT
            employee_id,
            basic_salary,
            allowance
        FROM employees
        WHERE active = TRUE
        ORDER BY employee_id
    LOOP

        -- Calculate gross pay.

        v_gross_pay :=
            v_employee.basic_salary + v_employee.allowance;


        -- Calculate net pay using the function.

        v_net_pay := fn_net_pay(v_employee.employee_id);


        -- Insert only if the employee/month record
        -- does not already exist.

        INSERT INTO payroll (
            employee_id,
            pay_month,
            gross_pay,
            net_pay
        )
        VALUES (
            v_employee.employee_id,
            p_month,
            v_gross_pay,
            v_net_pay
        )
        ON CONFLICT (employee_id, pay_month)
        DO NOTHING;

    END LOOP;

    RAISE NOTICE
        'Payroll processing completed for %',
        p_month;

END;
$$;


-- ============================================================
-- 11. PROCESS THE PREVIOUS MONTH'S PAYROLL
-- ============================================================

CALL pr_process_payroll(
    (
        DATE_TRUNC('month', CURRENT_DATE)
        - INTERVAL '1 month'
    )::DATE
);


-- ============================================================
-- 12. PROCESS THE CURRENT MONTH'S PAYROLL
-- Provides payroll records for a second month.
-- ============================================================

CALL pr_process_payroll(
    DATE_TRUNC('month', CURRENT_DATE)::DATE
);


-- ============================================================
-- 13. TEST REPROCESSING
-- Running this again must not change existing payroll rows.
-- ============================================================

CALL pr_process_payroll(
    (
        DATE_TRUNC('month', CURRENT_DATE)
        - INTERVAL '1 month'
    )::DATE
);


-- ============================================================
-- 14. CREATE PAYROLL REPORT VIEW
-- Includes historical records even if an employee
-- later becomes inactive.
-- ============================================================

CREATE OR REPLACE VIEW v_payroll_report AS
SELECT
    p.payroll_id,
    e.employee_id,
    e.full_name,
    p.pay_month,
    p.gross_pay,
    p.net_pay
FROM payroll p
INNER JOIN employees e
    ON p.employee_id = e.employee_id;


-- ============================================================
-- 15. CREATE INDEX FOR PAYROLL MONTH REPORTS
-- The existing unique index starts with employee_id.
-- This separate index supports searches by pay_month.
-- ============================================================

CREATE INDEX idx_payroll_pay_month
ON payroll (pay_month);


-- ============================================================
-- 16. TEST THE NET PAY FUNCTION
-- ============================================================

SELECT
    employee_id,
    full_name,
    fn_net_pay(employee_id) AS calculated_net_pay
FROM employees
ORDER BY employee_id;


-- ============================================================
-- 17. DISPLAY EMPLOYEE INFORMATION
-- ============================================================

SELECT *
FROM employees
ORDER BY employee_id;


-- ============================================================
-- 18. DISPLAY SALARY AUDIT RECORDS
-- ============================================================

SELECT *
FROM salary_audit
ORDER BY audit_id;


-- ============================================================
-- 19. DISPLAY PAYROLL REPORT
-- ============================================================

SELECT *
FROM v_payroll_report
ORDER BY pay_month, employee_id;


-- ============================================================
-- 20. EXPLAIN QUERY FOR THE PAY_MONTH INDEX
-- Searches all employees for a selected payroll month.
-- ============================================================

EXPLAIN
SELECT
    payroll_id,
    employee_id,
    pay_month,
    gross_pay,
    net_pay
FROM payroll
WHERE pay_month >=
      (
          DATE_TRUNC('month', CURRENT_DATE)
          - INTERVAL '1 month'
      )::DATE
  AND pay_month <
      (
          DATE_TRUNC('month', CURRENT_DATE)
          + INTERVAL '1 month'
      )::DATE;


-- ============================================================
-- 21. SCHEDULE MONTHLY PAYROLL AT 02:00
-- Runs on the first day of every month.
-- Processes the first day of the previous month.
-- Requires pg_cron to be installed and configured.
-- ============================================================

DO $$
DECLARE
    v_job RECORD;
BEGIN

    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron';

    -- Remove an older job with the same name, if present.

    FOR v_job IN
        EXECUTE
        'SELECT jobid
         FROM cron.job
         WHERE jobname = $1'
        USING 'ict371_monthly_payroll'
    LOOP
        EXECUTE 'SELECT cron.unschedule($1)'
        USING v_job.jobid;
    END LOOP;


    -- Schedule payroll for 02:00 on the first day
    -- of every month.

    EXECUTE
        'SELECT cron.schedule($1, $2, $3)'
    USING
        'ict371_monthly_payroll',
        '0 2 1 * *',
        'CALL pr_process_payroll(
            (DATE_TRUNC(''month'', CURRENT_DATE)
             - INTERVAL ''1 month'')::DATE
        );';

    RAISE NOTICE
        'Monthly payroll job scheduled for 02:00 on the first day of each month';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE
            'pg_cron could not be configured: %. Other SQL objects were created.',
            SQLERRM;
END;
$$;


-- ============================================================
-- 22. FINAL TABLE COUNTS
-- ============================================================

SELECT COUNT(*) AS total_employees
FROM employees;

SELECT COUNT(*) AS active_employees
FROM employees
WHERE active = TRUE;

SELECT COUNT(*) AS inactive_employees
FROM employees
WHERE active = FALSE;

SELECT COUNT(*) AS total_payroll_records
FROM payroll;

SELECT COUNT(*) AS total_salary_audit_records
FROM salary_audit;


-- ============================================================
-- END OF QUESTION 6
-- ============================================================


/*
OPTIONAL JOB INSPECTION

Run these queries separately if pg_cron was successfully
installed and configured.

1. Inspect the scheduled job:

SELECT jobid, jobname, schedule, command, active
FROM cron.job
WHERE jobname = 'ict371_monthly_payroll';

2. Inspect the job's run history:

SELECT
    jobid,
    runid,
    status,
    return_message,
    start_time,
    end_time
FROM cron.job_run_details
WHERE jobid = (
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'ict371_monthly_payroll'
)
ORDER BY start_time DESC;
*/
