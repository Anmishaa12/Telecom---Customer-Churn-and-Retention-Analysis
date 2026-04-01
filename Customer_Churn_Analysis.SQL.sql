-- =============================================
-- PROJECT: Customer Churn Analysis & Retention Strategy
-- INDUSTRY: Telecom
-- TOOL: MySQL
-- AUTHOR: Anmisha
-- =============================================

-- =============================================
-- DATA QUALITY CHECKS & CLEANING
-- =============================================
SET SQL_SAFE_UPDATES = 0;
-- Replace empty strings with 'Not Applicable' in service columns
UPDATE customer_data SET online_security = 'Not Applicable' WHERE online_security = '';
UPDATE customer_data SET online_backup = 'Not Applicable' WHERE online_backup = '';
UPDATE customer_data SET device_protection_plan = 'Not Applicable' WHERE device_protection_plan = '';
UPDATE customer_data SET premium_support = 'Not Applicable' WHERE premium_support = '';
UPDATE customer_data SET streaming_tv = 'Not Applicable' WHERE streaming_tv = '';
UPDATE customer_data SET streaming_movies = 'Not Applicable' WHERE streaming_movies = '';
UPDATE customer_data SET streaming_music = 'Not Applicable' WHERE streaming_music = '';

-- Verify all empty strings are replaced
SELECT 
    COUNT(CASE WHEN online_security = '' THEN 1 END) AS sec_blanks,
    COUNT(CASE WHEN premium_support = '' THEN 1 END) AS sup_blanks,
    COUNT(CASE WHEN streaming_tv = '' THEN 1 END) AS tv_blanks
FROM customer_data;

-- Check for duplicate Customer IDs
-- Check for duplicate Customer IDs
select Customer_ID, count(*) as count
from customer_data
group by Customer_ID
having count(*) > 1;
-- Result: 0 rows — no duplicate Customer IDs found
-- Every customer has a unique identifier

-- Check NULL counts across key columns
select 
    sum(case when Customer_ID is null then 1 else 0 end)      as null_customer_id,
    sum(case when Monthly_Charge is null then 1 else 0 end)   as null_monthly_charge,
    sum(case when Customer_Status is null then 1 else 0 end)  as null_status,
    sum(case when Contract is null then 1 else 0 end)         as null_contract,
    sum(case when Total_Revenue is null then 1 else 0 end)    as null_revenue
FROM customer_data;
-- Result: Only Monthly_Charge has 1 NULL (the negative value we set to NULL)

-- Check for outliers in Age
select 
    min(Age) as min_age,
    max(Age) as max_age,
    round(AVG(Age), 1) as avg_age
from customer_data;
-- Result: Min age: 18, max age: 85, and average age: 47.1
-- No outliers detected -- age range is realistic for telecom customers


-- Check distinct values in key categorical columns
select distinct  Customer_Status from customer_data;
-- Result: Churned, Stayed, Joined

select distinct  Contract from customer_data;
-- Result: Month-to-Month, One Year, Two Year

select distinct Internet_Type from customer_data;
-- Result: Cable, Fiber Optic, DSL, None

-- Checked for negative monthly charges
select count(*) from customer_data where monthly_charge <= 0;
-- Found: 1 row with -$4 charge -- set to NULL

-- Checked service columns for empty strings
select count(*) from customer_data where online_security = '';
-- Found: 1,390 empty strings -- updated to 'Not Applicable'
-- Reason: customers without internet service cannot have online security

--  Verified unique status of customers
select distinct customer_status from customer_data;
-- Excluded 'Joined' customers from churn analysis
-- Reason: joined customers have not completed a billing cycle
--         including them would understate churn rate

--  Verified tenure range: MIN=1, MAX=36 months
select max(Tenure_in_Months), min(Tenure_in_Months)
from Customer_Data;
--  Verified minimum and maximum monthly charge range: MIN=$18.25, MAX=$118.75
select max(monthly_charge), min(monthly_charge)
from Customer_Data
where monthly_charge > 0;

-- NULL Monthly Charge Investigation
select 
    Customer_Status,
    count(*) as null_charge_count
from customer_data
where Monthly_Charge is null
group by Customer_Status;

-- Result: Stayed: 74 | Churned: 27 | Joined: 6 | Total: 107
-- Finding: NULL charges spread across all customer statuses
-- indicating a data quality/billing system issue
-- Decision: Excluded from price-based analysis using 
-- IS NOT NULL filter. Remaining metrics unaffected.
-- Action: In production environment would flag to data 
-- engineering team to investigate root cause.
-- =============================================
-- METRIC 1: Overall Churn Rate
-- Business Question: What is the overall churn rate?
select 
count(*) as total_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0
        / count(*), 2) as churn_rate_pct,
round(sum(case when customer_status = 'stayed' then 1 else 0 end) * 100.0
        / count(*), 2) as retention_rate_pct
from customer_data
where customer_status in ('stayed','churned');

-- Result : 6007 customers | 1,732 churned | churn rate : 28.83%
-- Insight : churn rate of 28.83% exceeds industry benchmark of 25%
-- Recommendation : Investigate root causes across contract type, pricing, premium services, and implemented targeted retention 
-- across high group segments to close the 4 point gap.


-- =============================================
-- METRIC 2a: Who is churning - By contract type?
-- Business Question: Which contract type has the highest churn?
select contract,
count(*) as total_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) AS stayed_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0 / 
count(*),2) as churn_rate_pct
from customer_data
where customer_status in ('churned','stayed')
group by contract
order by churn_rate_pct desc;

-- RESULT: Month-to-Month: 1,529 churned | 52.38% churn
--         One Year      : 156 churned   | 11.23% churn
--         Two Year      : 47 churned    | 2.77%  churn
-- Insight : churn rate of 52.38% exceeds double the industry benchmark of 25%
-- Two Year customers churn at only 2.77% -- 19x lower. Contract type is the strongest single
-- predictor of churn in this dataset.
-- Recommendation : Offer incentives such as discounts or loyalty rewards to Month-to-Month customers to encourage upgrades
--  to One Year or Two Year contracts — reducing exposure to 52% churn risk."


-- =============================================
-- METRIC 2b: Who is churning - By pricing?
-- Business Question: Which pricing group has the highest churn?
select
case
when monthly_charge is null then 'unknown'
when monthly_charge < 30 then 'Low(<$30)'
when monthly_charge >= 30 and monthly_charge <= 65 then 'Mid ($30-65)'
when monthly_charge > 65 then 'High (>$65)'
end as price_group_bins,
count(*) as total_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as stayed_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0 / 
count(*),2) as churn_rate_pct
from customer_data
where customer_status in ('churned','stayed')
and monthly_charge is not null
group by price_group_bins
order by churn_rate_pct desc;

-- Result : High charges(>$65) | 1,233 churned | churn rate : 36.23%
--          Medium charges($30-65) | 321 churned | churn rate : 26.46%
--          Low charges(<$30)| 151 churned | churn rate : 11.71%
-- Insight : High paying customers are more likely to churn at 36.23%. As monthly charges increases churn rate
--           increases consistently among all 3 groups.
-- Recommendation : Introduce promotional offers or discounts to the higher paying customers, this segment churns at 36.23%
--                  indicating clear price sensitivity.


-- =============================================
-- METRIC 2c: Who is churning - By tenure?
-- Business Question: At which tenure stage is churn highest?
select 
case
when tenure_in_months <= 12 then '0-12 months'
when tenure_in_months <= 24   then '13-24 months'
else '25-36 months'
end as tenure_group,
count(*) as total_customers,
SUM(CASE WHEN customer_status = 'stayed' THEN 1 ELSE 0 END) AS stayed_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0 / 
count(*),2) as churn_rate_pct
from customer_data
where customer_status in ('churned','stayed')
group by tenure_group
order by churn_rate_pct desc;

-- Result : 0-12 months | 684 churned | churn rate : 29.18%
--          13-24 months | 494 churned | churn rate : 28.04%
--          25-36 months | 527 churned | churn rate : 29.28%
-- Insight : Churn is uniform at ~29% across all tenure groups -- meaning 
--           long term customers are just as likely to leave as new customers.
--           The company has no loyalty mechanism working at any stage 
--           of the customer lifecycle.
-- Recommendation : The business should introduce onboarding incentives such as discounted protection services for 0-12 month customers to improve early retention,
--                  and implement a loyalty reward program for customers staying beyond 24 months — currently these customers receive no recognition or 
--                   benefit for their long term commitment."


-- =============================================
-- METRIC 2d: Who is churning - By online security?
-- Business Question: Does having online security reduce churn?
select online_security,
count(*) as total_customers,
sum(case when customer_status = 'churned' then 1 else 0 end) as churned_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0
/count(*),2)  as churn_rate_pct
from customer_Data
where customer_status in ('stayed','churned') and
online_security != 'Not Applicable'
group by online_security
order by churn_rate_pct desc;

-- Result : With online security | 266 churned | 14.94%
--          Without online security | 1,357 churned | 45.19%
-- Insight : Customers without Online Security churn at 45.19% vs 14.94% with it
--          a 30 percentage point difference. Having Online Security reduces
--          churn risk by 3x. This is the strongest service-level retention  signal in the dataset.
-- Recommendation : Bundle Online Security as a default or discounted add-on for new customers — 
--                  customers without it churn at 45% compared to 15% with it, a 30 point difference


-- =============================================
-- METRIC 2e: Who is churning - By premium support?
-- Business Question: Does having premium support reduce churn?
select premium_support,
count(*) as total_customers,
sum(case when customer_status = 'churned' then 1 else 0 end) as churned_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0
/count(*),2)  as churn_rate_pct
from customer_Data
where customer_status in ('stayed','churned') and
premium_support != 'Not Applicable'
group by premium_support
order by churn_rate_pct desc;

-- Result : With premium support | 286 churned | 15.77%
--          Without premium support | 1,337 churned | 45.00%
-- Insight : Customers without premium support are likely to churn at 45.00% vs 15.77% with it 30% percentage point difference
--           Having premium support reduce churn by 3x.
-- Recommendation : Promote Premium Support adoption especially for high price and Month-to-Month customers — without it churn is 45%,
--                  with it churn drops to 15.8%.



-- =============================================
-- METRIC 3: Price vs churn?
-- Business Question: Analyzing how churn varies across different pricing levels?
select
case
when monthly_charge < 30 then 'Low(<$30)'
when monthly_charge >= 30 and monthly_charge <= 65 then 'Mid ($30-65)'
when monthly_charge > 65 then 'High (>$65)'
end as price_group_bins,
count(*) as total_customers,
ROUND(AVG(monthly_charge), 2) AS avg_monthly_charge,
SUM(CASE WHEN customer_status = 'stayed' THEN 1 ELSE 0 END) AS stayed_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0 / 
count(*),2) as churn_rate_pct
from customer_data
where customer_status in ('churned','stayed')
and monthly_charge > 0
group by price_group_bins
order by churn_rate_pct desc;


-- Result : High price group | 1,233 churned | churn rate : 36.23%
--          Medium price group | 321 churned | churn rate : 26.46%
--          Low price group | 151 churned | churn rate : 11.71%
-- Insight : High price customers paying avg $88.76/month churn at 36.23% --
--          3x higher than low price customers at 11.71%. As monthly charge  
--          increases, churn rate increases consistently. clear evidence
--          of price sensitivity across all three segments
-- Recommendation : High price customers paying an average of $88.76 per month churn at 36.23% — the highest of any price segment. 
--                  The business should introduce loyalty discounts or price matching offers for this segment to reduce price sensitivity and 
--                  prevent revenue loss from the highest paying customers.


-- =============================================
-- METRIC 4: Do Services Reduce Churn?
-- Business Question: Do additional services reduce churn risk?
-- Note: Online Security (Metric 2D) and Premium Support (Metric 2E) 
--       analyzed separately. Combined results below.
-- =============================================
-- METRIC 4a : Streaming tv vs churn
select streaming_tv,
count(*) as total_customers,
sum(case when customer_status = 'churned' then 1 else 0 end) as churned_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0
/count(*),2)  as churn_rate_pct
from customer_Data
where customer_status in ('stayed','churned') and
streaming_tv != 'Not Applicable'
group by streaming_tv
order by churn_rate_pct desc;

-- METRIC 4b : Streaming movies vs churn
select streaming_movies,
count(*) as total_customers,
sum(case when customer_status = 'churned' then 1 else 0 end) as churned_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0
/count(*),2)  as churn_rate_pct
from customer_Data
where customer_status in ('stayed','churned') and
streaming_movies != 'Not Applicable' 
group by streaming_movies
order by churn_rate_pct desc;


-- METRIC 4c : Streaming music vs churn
select streaming_music,
count(*) as total_customers,
sum(case when customer_status = 'churned' then 1 else 0 end) as churned_customers,
sum(case when customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0
/count(*),2)  as churn_rate_pct
from customer_Data
where customer_status in ('stayed','churned') and
streaming_music != 'Not Applicable' 
group by streaming_music
order by churn_rate_pct desc;


-- Result : Online Security  : No = 45.19% | Yes = 14.94% | Difference = 30 points
--          Premium Support  : No = 45.00% | Yes = 15.77% | Difference = 29 points
--          Streaming TV     : No = 37.05% | Yes = 30.89% | Difference = 6 points
--          Streaming Movies : No = 37.08% | Yes = 30.95% | Difference = 6 points
--          Streaming Music  : No = 36.98% | Yes = 30.38% | Difference = 6 points
-- Insight : Streaming doesn't protect retention strongly, without premium support and with streaming services price just adds up to the monthly charge
--           without any online protection
-- Recommendation : The business should bundle at least one protection service as default for Month-to-Month and high price customers, 
--                  who already churn at 52% and 36% respectively, to maximize retention impact.



-- =============================================
-- METRIC 5: Tenure lifecycle?
-- Business Question: Analyzing churn across different customer lifecycle stages based on tenure.
select 
case
when tenure_in_months <= 12 then '0-12 months'
when tenure_in_months <= 24   then '13-24 months'
else '25-36 months'
end as tenure_group,
count(*) as total_customers,
SUM(CASE WHEN customer_status = 'stayed' THEN 1 ELSE 0 END) AS stayed_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
round(avg(monthly_charge),2) as average_monthly_charge,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0 / 
count(*),2) as churn_rate_pct
from customer_data
where customer_status in ('churned','stayed')
and monthly_charge > 0
group by tenure_group
order by churn_rate_pct desc;


-- Result : 0-12 months | 684 churned | churn rate : 29.18% | average charge : $66.28
--          13-24 months | 494 churned | churn rate : 28.04% | average charge : $66.21
--          25-36 months | 527 churned | churn rate : 29.28% | average charge : $66.4
-- Insight : Churn is uniform at 29% acrosss all tenure groups and average monthly charge is also uniform,
--           that means old customers are also paying as new customers, and they tend to leave as newer ones. 
-- Recommendation : Company should introduce loyalty perks for 25-36 month customers, includes protection services as an add-on 
--                  in their monthly charge or at discounted prices to reduce the churn at higher group.
--                  Since they receive no financial benifit for long-term consistency.
--                  For 0-12 month customers improve onboarding experience by offering at least one protection service at discounted price
--                 to increase early dependency and reduce first year churn.



-- =============================================
-- METRIC 6: Contract type?
-- Business Question: Analyzing churn across different contract types.
select contract,
count(*) as total_customers,
SUM(CASE WHEN customer_status = 'stayed' THEN 1 ELSE 0 END) AS stayed_customers,
sum(case when customer_status = 'churned' then 1 else 0 end)  as churned_customers,
ROUND(AVG(monthly_charge), 2) AS avg_monthly_charge,
round(sum(case when customer_status = 'churned' then 1 else 0 end) * 100.0 / 
count(*),2) as churn_rate_pct,
case WHEN contract = 'month-to-month' then 'High risk'
when contract = 'one year' then 'Medium risk'
else 'Low risk' end as risk_category
from customer_data
where customer_status in ('churned','stayed')
group by contract
order by churn_rate_pct desc;


-- Result : Month-to-Month | 1,529 churned | avearge monthly charge : $68.53 | churn rate : 52.38%
--          One year | 156 churned | avearge monthly charge : $66.3 | churn rate : 11.23%
--          Two year | 47 churned | avearge monthly charge : $62.44 | churn rate : 2.77%
-- Insight : Month-to-Month customers churn at 52.38% — more than double our 25% industry benchmark, they don't have a commitment towards company.
--           But, each contract group are paying $65 on an average, two year customers didn't receiving any
--           financial benifit. 
-- Recommendation : The business should improve onboarding for new Month-to-Month customers by offering discounted
--                  protection services or one free streaming service to encourage longer commitment. Additionally, 
--                  since all three contract groups pay similar average monthly charges of $62-$68, the business should introduce loyalty rewards for 
--                  One Year and Two Year customers — currently long term customers receive no financial benefit for their 
--                  commitment, which is a missed retention opportunity. 


-- =============================================
-- METRIC 7: Revenue impact?
-- Business Question: How much revenue we are losing due to churn.
select customer_status,
count(*) as total_customers,
concat('$', format(round(sum(total_revenue), 2), 2)) as revenue,
concat('$', format(round(avg(total_revenue), 2), 2)) as average_revenue
from customer_Data
where customer_status in ('stayed','churned')
group by customer_status;


-- Result : 4,275 stayed | Total revenue : $16M | Lifetime average revenue per customer : $3,745.06
--          1,732 churned | Total revenue : $3.4M | Lifetime average revenue per customer : $1,969.95
-- Insight : We are losing $3.4M in revenue from 1,732 churned customers who pay $73/month on average — 
--           higher than retained customers at $61/month
-- Recommendation : To protect this high value segment the business should: 
--                  (1) target Month-to-Month high charge customers with contract upgrade incentives, 
--                  (2) bundle protection services at discounted prices to increase dependency and reduce churn risk, and
--                  (3) respond to competitor pressure by improving device offerings and data packages for high paying customers.



-- =============================================
-- METRIC 8a: Why customers are churning?
-- Business Question: Identifying churn categories and the customers churned in each reason.
select churn_category,
count(*) as churn_count,
round(count(*) * 100.0 / sum(count(*)) over (), 2) as churn_pct
from customer_data
where customer_status = 'churned'
group by Churn_Category
order by churn_count desc;


-- Result : competitor | 761 churned | 43.94%
--          Attitude | 301 churned | 17.38%
--          Dissatisfaction | 300 churned |17.32%
--          price | 196 churned | 11.32%
--          other | 174 churned | 10.05%
-- Insight : -- Insight : Competitor is the dominant churn category at 43.94% -- nearly 
--           half of all churned customers left due to competitor advantages.
--           Attitude (17.38%) is the second largest category and the most
--           actionable since it is an internal problem the business can fix.
-- Recommendation : Churn reasons in competitor category is better devices, better offers and high speed networks.
--                  Jammu and kashmir, Assam are the regions where we noticed due to competitor category.




-- =============================================
-- METRIC 8b: Why customers are churning?
-- Business Question: Identifying churn categories and churn reasons.
with category as (
    select 
        churn_category, Churn_Reason,
        count(*) as churn_count
    from customer_data
    where customer_status = 'churned'
    group by churn_category, Churn_Reason
)
select 
    churn_category, churn_reason,
    churn_count,
    round(churn_count * 100.0 / sum(churn_count) over (), 2) as churn_pct
from category
order by churn_count desc
limit 10;


-- Result : Category : Competitor | 761 churned | Reason : better offers, better devices
--          Category : Attitude | 301 churned | Reason : attitude of service provider
--          Category : Dissatisfaction | 300 churned | Reason : product dissatisfaction and network reliability
-- Insight : Competitor-driven churn accounts for 44% of all churn — customers are leaving for better devices, offers, and speeds.
-- Recommendation  : The business should launch a device upgrade program and competitive price matching for at-risk customers, with special focus on J&K where churn is 58.5%.
--                   Attitude-related churn accounts for 17% — 301 customers cited poor support behavior, 
--                   which is entirely within the company's control. The business should implement targeted customer service training, 
--                   quality monitoring of support interactions, and performance coaching for underperforming agents




-- =============================================
-- METRIC 9: Geographical segmentation?
-- Business Question: Identifying the regions where churn is the highest.
select  state,
count(*) as total_customers,
sum(case when  customer_status = 'churned' then 1 else 0 end) as churned_customers,
sum(case when  customer_status = 'stayed' then 1 else 0 end) as retained_customers,
round(sum(case when  customer_status = 'churned' then 1 else 0 end) * 100.0 / count(*),2) as churn_rate_pct
from customer_data 
where customer_status in ('churned','stayed')
group by state 
having count(*) >= 50
order by churn_rate_pct desc;



-- -- Result : Top 5 states by churn rate (min 50 customers):
--             Jammu & Kashmir | 313 customers | 183 churned | 58.47%
--             Assam           | 129 customers |  53 churned | 41.09%
--            Jharkhand       | 105 customers |  39 churned | 37.14%
--            Chhattisgarh    |  55 customers |  18 churned | 32.73%
--            Delhi           | 119 customers |  38 churned | 31.93%
--            National Average: 28.83%
-- Insight : Jammu & Kashmir shows a 58.5% churn rate — double the national average.
--           Assam and Jharkhand follow at 41% and 37% respectively.
-- Recommendation : The business should conduct a regional investigation in these states focusing on two areas: 
--                  (1) network quality and speed improvements to counter competitor pressure, and 
--                  (2) regional customer service training and quality monitoring to address attitude-related churn. 
--                  A targeted retention campaign with location-specific offers and device upgrades should be launched in J&K as the highest priority market.
