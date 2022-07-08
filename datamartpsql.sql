-- data has been inserted (17117 rows) , please refer to the case details

-- Cleaning data
-- A. Data Cleansing Steps

DROP TABLE IF EXISTS temp_weekly_sales;
CREATE TEMP TABLE temp_weekly_sales AS
SELECT 
    CAST(('20' || SPLIT_PART(week_date,'/','3') || '-0' || SPLIT_PART(week_date,'/','2') || '-' || SPLIT_PART(week_date,'/','1')) AS DATE) week_date,
        -- somehow the TO_DATE in this function is not working in order to get the week_date in DATE type, 
        -- thus i am using splitting part approach
    DATE_PART('week', TO_DATE(week_date, 'DD/MM/YY')) AS week_number,
    DATE_PART('month', TO_DATE(week_date, 'DD/MM/YY')) AS month_number,
    DATE_PART('year', TO_DATE(week_date, 'DD/MM/YY')) AS calendar_year,
    region,
    platform,
    CASE WHEN segment = 'null' THEN 'Unknown' ELSE segment END segment,
    CASE WHEN SUBSTRING(segment,2,1)= '1' THEN 'Young Adults' 
        WHEN SUBSTRING(segment,2,1)= '2' THEN 'Middle Aged'
        WHEN SUBSTRING(segment,2,1) IN ('3', '4') THEN 'Retirees'
        ELSE 'Unknown' END age_band,
    CASE WHEN SUBSTRING(segment,1,1)= 'C' THEN 'Couples'
        WHEN SUBSTRING(segment,1,1)= 'F' THEN 'Families'
        ELSE 'Unknown' END demographic,
    customer_type,
    transactions,
    sales,
    ROUND(sales / transactions,2) avg_transaction
FROM weekly_sales;

-- B. Data Exploration
-----------------------
-- B.1 What day of the week is used for each week_date value?
-- TO_CHAR function
SELECT 
    DISTINCT TO_CHAR(week_date, 'Day') AS weekday
FROM temp_weekly_sales;

-- B.2 What range of week numbers are missing from the dataset?
WITH cte_all_week AS ( 
    SELECT GENERATE_SERIES (1,52) week_number
)
SELECT week_number 
FROM cte_all_week
WHERE week_number NOT IN (
    SELECT 
        DISTINCT week_number
    FROM temp_weekly_sales
    )
ORDER BY 1;

-- B.3 How many total transactions were there for each year in the dataset?
SELECT
    calendar_year,
    SUM(transactions) total_transaction
FROM temp_weekly_sales
GROUP BY 1
ORDER BY 1;

-- B.4 What is the total sales for each region for each month?
SELECT 
    region,
    month_number,
    calendar_year,
    SUM(sales) 
FROM temp_weekly_sales
GROUP BY 1,2,3
ORDER BY 3,2,1

-- B.5 What is the total count of transactions for each platform?
SELECT
    platform, 
    COUNT(*)
FROM temp_weekly_sales
GROUP BY 1

-- B.6 What is the percentage of sales for Retail vs Shopify for each month?
WITH cte AS( 
SELECT 
    month_number,
    calendar_year,
    SUM(CASE WHEN platform = 'Retail' THEN sales ELSE 0 END) retail_sales,
    SUM(CASE WHEN platform = 'Shopify' THEN sales ELSE 0 END) shopify_sales,
    SUM(sales) total_sales
FROM temp_weekly_sales
GROUP BY 1,2
)
SELECT 
   month_number,
   calendar_year, 
   ROUND((100*retail_sales/total_sales),2) pct_retail,
   ROUND((100*shopify_sales/total_sales),2) pct_shopify
FROM cte   
   

-- B.7 What is the percentage of sales by demographic for each year in the dataset?
SELECT 
    calendar_year,
    demographic,
    SUM(sales) annual_sales,
    ROUND((100*SUM(sales)/SUM(SUM(sales)) OVER (PARTITION BY demographic)),2) as pct
FROM temp_weekly_sales
GROUP BY 1,2
ORDER BY 1,2;


-- B.8 Which age_band and demographic values contribute the most to Retail sales?
-- I looked at the combination of age_band and dempgraphic, since for the age_band and
-- demographic individually can be done the same way. will do when later I write the 
-- executive summary
SELECT 
    age_band,
    demographic,
    SUM(sales) total_sales,
    ROUND(100*SUM(sales)/(SUM(SUM(sales)) OVER ()),2) as pct
FROM temp_weekly_sales
WHERE platform = 'Retail'
GROUP BY 1,2
ORDER BY 3 DESC;

SELECT * FROM weekly_sales

-- B.9 Can we use the avg_transaction column to find the average transaction size for each year for Retail vs Shopify? If not - how would you calculate it instead?
-- no we cannot use the average transaction, it violates the arithmetic rule. 
-- the calculation should be totalling the sales and transactions first. Then divid the total sales against total transactions

SELECT
    platform, 
    calendar_year,
    ROUND(AVG(avg_transaction),2) average_fr_average, 
    SUM(sales) /SUM(transactions) average_real
FROM temp_weekly_sales
GROUP BY 1,2
ORDER BY 1,2


-- C. Analysis using Date reference
-------------------------------
-- C.1 What is the total sales for the 4 weeks before and after 2020-06-15? What is the growth or reduction rate in actual values and percentage of sales?
-- first we need to know 2020-06-15 lies in which week number. constraint by year 2020.
SELECT 
    DATE_PART('week','2020-06-15'::DATE) week_number
-- 4 weeks before are week# 21,22,23,24 . 4 weeks after the date are week# 25,26,27,28. week#25 is included
-- there are several ways to achieve this

WITH cte_before AS(
SELECT
    week_number,
    SUM(sales) sales_before,
    ROW_NUMBER() OVER(ORDER BY week_number) row_num
FROM temp_weekly_sales
WHERE calendar_year = '2020' 
    AND week_number IN (21,22,23,24)
GROUP BY 1
), cte_after AS(
SELECT
    week_number,
    SUM(sales) sales_after,
    ROW_NUMBER() OVER(ORDER BY week_number) row_num
FROM temp_weekly_sales
WHERE calendar_year = '2020' 
    AND week_number IN (25,26,27,28)
GROUP BY 1
)
SELECT 
    SUM(t1.sales_before) total_before,
    SUM(t2.sales_after) total_after,
    SUM(t2.sales_after-t1.sales_before) difference,
    ROUND(100*(SUM(t2.sales_after-t1.sales_before)/SUM(t1.sales_before)),2) pct_change
FROM cte_before t1
JOIN cte_after t2
ON t1.row_num = t2.row_num;     

-- C.2 What about the entire 12 weeks before and after?
-- lets use simpler approach now. 25 - 12 = 13. 13 to 24 is 12 weeks before. 25 to 36 is after
WITH cte_summary AS(
SELECT
    week_number,
    SUM(CASE WHEN week_number BETWEEN 13 AND 24 THEN sales ELSE 0 END) sales_before,
    SUM(CASE WHEN week_number BETWEEN 25 AND 36 THEN sales ELSE 0 END) sales_after
FROM temp_weekly_sales
WHERE calendar_year = '2020' 
GROUP BY 1
)
SELECT 
    SUM(sales_before) total_before,
    SUM(sales_after) total_after,
    SUM(sales_after)-SUM(sales_before) difference,
    ROUND(100*(SUM(sales_after)-SUM(sales_before))/SUM(sales_before),2) pct_change
FROM cte_summary


-- C.3 How do the sale metrics for these 2 periods before and after compare with the previous years in 2018 and 2019?
-- I will try to answer only for Question C.2 --> for 12 weeks
WITH cte_summary AS(
SELECT
    calendar_year,
    SUM(CASE WHEN week_number BETWEEN 13 AND 24 THEN sales ELSE 0 END) sales_before,
    SUM(CASE WHEN week_number BETWEEN 25 AND 36 THEN sales ELSE 0 END) sales_after
FROM temp_weekly_sales
GROUP BY 1
)
SELECT 
    calendar_year,
    SUM(sales_before) total_before,
    SUM(sales_after) total_after,
    SUM(sales_after)-SUM(sales_before) difference,
    ROUND(100*(SUM(sales_after)-SUM(sales_before))/SUM(sales_before),2) pct_change
FROM cte_summary
GROUP BY 1
ORDER BY 1


