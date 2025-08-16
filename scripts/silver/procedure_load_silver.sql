/*
===============================================================================
Stored Procedure: Load Silver Layer (Source -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process 
	to populate the 'silver' schema tables from the 'bronze' schema.
  Actions Performed:
	  - Truncate Silver Tables.
	  - Inserts transformed and cleansed data from Bronze intro Silver Tables.

Parameters:
    None. 
	This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC bronze.load_silver;
===============================================================================
*/

-- insertion to crm_cust_info

CREATE OR ALTER PROCEDURE bronze.load_silver AS
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @start_batch_time DATETIME, @end_batch_time DATETIME;
	BEGIN TRY
	SET @start_batch_time = GETDATE();
		PRINT'=======================================================================';
		PRINT'loading Silver Layer';
		PRINT'=======================================================================';

		PRINT '----------------------------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '----------------------------------------------------------------------';

		SET @start_time = GETDATE();
			PRINT '>> Truncating Table: silver.crm_cust_info';
			TRUNCATE TABLE silver.crm_cust_info;
			PRINT '>> Inserting Data Into: silver.crm_cust_info';
			INSERT INTO silver.crm_cust_info(
				cst_id,
				cst_key,
				cst_firstname,
				cst_lastname,
				cst_marital_status,
				cst_gndr,
				cst_create_date
			)

			SELECT 
				cst_id,
				cst_key,
				TRIM(cst_firstname) as cst_firstname,
				TRIM(cst_lastname) as cst_lasttime,
				CASE
					WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
					WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
					ELSE 'N/A'
				END AS cst_marital_status, --normalize marital status value to readable values
				CASE
					WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
					WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
					ELSE 'N/A'
				END AS cst_gndr, -- normalize gender value to readable values
				cst_create_date
				FROM (
					SELECT 
						*,
						ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
						FROM bronze.crm_cust_info
						WHERE cst_id IS NOT NULL
					)t
				WHERE flag_last = 1
				SET @end_time = GETDATE();
					PRINT '>> Load Duration Time: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
					PRINT '>> -------------------';

			-- insertion to crm_prd_info
		SET @start_time = GETDATE();
			PRINT '>> Truncating Table: silver.crm_prd_info';
			TRUNCATE TABLE silver.crm_prd_info;
			PRINT '>> Inserting Data Into: silver.crm_prd_info';
			INSERT INTO silver.crm_prd_info(
				prd_id,
				cat_id,
				prd_key,
				prd_nm,
				prd_cost,
				prd_line,
				prd_start_dt,
				prd_end_dt
			)
			SELECT
				prd_id,
				REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id, -- extract category id
				SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,	-- extract product id
				prd_nm,
				ISNULL(prd_cost,0) AS prd_cost,
				CASE
					WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
					WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
					WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
					WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'	
					ELSE 'N/A'
				END AS prd_line, -- map product line codes to descriptive values
				CAST(prd_start_dt as DATE) AS prd_start_dt,
				CAST(
					LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1 AS DATE
					) AS prd_end_dt -- Calculate end date as one day before the next start date
				FROM bronze.crm_prd_info;
			SET @end_time = GETDATE();
			PRINT '>> Load Duration Time: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
			PRINT '>> -------------------';
			
			-- insertion to crm_sales_details
			SET @start_time = GETDATE();
			PRINT '>> Truncating Table: silver.crm_sales_details';
			TRUNCATE TABLE silver.crm_sales_details;
			PRINT '>> Inserting Data Into: silver.crm_sales_details';
			INSERT INTO silver.crm_sales_details(
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				sls_order_dt,
				sls_ship_dt,
				sls_due_dt,
				sls_sales,
				sls_quantity,
				sls_price
			) 
			SELECT
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				CASE
					WHEN sls_order_dt = 0 OR LEN(sls_order_dt)  != 8 THEN NULL
					ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
				END AS sls_order_dt,
				CASE
					WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
					ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
				END AS sls_ship_dt,
				CASE 
					WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
					ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
				END AS sls_due_dt,
				CASE 
					WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
						THEN sls_quantity * ABS(sls_price)
					ELSE sls_sales
				END AS sls_sales, -- recalculate sales if orignal value is incorrect or missing
				sls_quantity,
				CASE 
					WHEN sls_price IS NULL OR sls_price <= 0
						THEN sls_sales/ NULLIF(sls_quantity,0)
					ELSE sls_price
				END AS sls_price
			FROM bronze.crm_sales_details;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration Time: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------';

		PRINT '----------------------------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '----------------------------------------------------------------------';
			-- insertion to erp_cust_az12
		SET @start_time = GETDATE();

			PRINT '>> Truncating Table: silver.erp_cust_az12';
			TRUNCATE TABLE silver.erp_cust_az12;
			PRINT '>> Inserting Data Into: silver.erp_cust_az12';
			INSERT INTO silver.erp_cust_az12(cid, bdate, gen)
			select
			CASE
				WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid,4, LEN(cid))
				ELSE cid
			END AS cid_new,

			CASE
				WHEN bdate > GETDATE() THEN NULL
				ELSE CAST(bdate AS DATE)
			END AS bdate,
			CASE
				WHEN UPPER(TRIM(gen)) IN ('F','FEMALE') THEN 'Female'
				WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
				ELSE 'N/A'
			END AS gen
			from bronze.erp_cust_az12;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration Time: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------';
			-- insertion to erp_loc_a101
		SET @start_time = GETDATE();

			PRINT '>> Truncating Table: silver.erp_loc_a101';
			TRUNCATE TABLE silver.erp_loc_a101;
			PRINT '>> Inserting Data Into: silver.erp_loc_a101';
			INSERT INTO silver.erp_loc_a101(cid, cntry)
			SELECT 
				REPLACE(cid, '-', ''),
				CASE
					WHEN TRIM(cntry) IN ('USA', 'US') THEN 'United States'
					WHEN TRIM(cntry) = 'DE' THEN 'Germany'
					WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'N/A'
					ELSE cntry
				END AS cntry -- Normalize and Handle missing or blank country codes
			FROM bronze.erp_loc_a101;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration Time: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------';
			-- insertion to erp_px_cat_g1v2
		SET @start_time = GETDATE();

			PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
			TRUNCATE TABLE silver.erp_px_cat_g1v2;
			PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
			INSERT INTO silver.erp_px_cat_g1v2(id, cat, subcat, maintenance)
			SELECT
				id,
				cat,
				subcat,
				maintenance
			FROM
				bronze.erp_px_cat_g1v2;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration Time: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------';

		SET @end_batch_time = GETDATE();
		PRINT '========================================';
		PRINT 'Loading Bronze Layer is Completed';
		PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(second, @start_batch_time, @end_batch_time) AS NVARCHAR) + ' seconds';
	
END TRY
	BEGIN CATCH
		PRINT '=======================================================================';
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER';
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_MESSAGE() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=======================================================================';
	END CATCH
END;
