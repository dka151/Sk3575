USE [WSS_APTOS]
GO
/****** Object:  StoredProcedure [mer].[MerchHierarchy_Hilco_test]    Script Date: 3/17/2026 6:34:34 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [mer].[MerchHierarchy_Hilco_test]
AS

BEGIN

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;



/**Merchandise Hierarchy Data Feed to Hilco - for 8 stores '0103', '0139', '0142', '0143', '0182', '0183', '0189', '0194'
Description - Weekly at end of Week
Scope as per WSS data request file provided by Sarah D on 02/26/2026
Script and Store Procedure created by Sherifat on 03/03/2026. 
Removed style active_flag = 'Y' and style color reorder_flag = 1 by Sherifat on 3/13/2026 to allow missing SKUs.
***/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;


----------------------all skus detail
SELECT top 5 s.sku_id, 
       ss.style_id,
	   sc.color_id,
	   c.color_code,
	   sc.extended_desc,
	   sm.size_master_id,
	   sm.size_code,
	   st.season_id,
	   se.season_code,
	   st.style_code
into  #tempsize
FROM [EPICORSQL].[me_wsl_01].[dbo].Style st with (nolock),
     [EPICORSQL].[me_wsl_01].[dbo].sku s with (nolock), 
     [EPICORSQL].[me_wsl_01].[dbo].style_color sc with (nolock), 
	 [EPICORSQL].[me_wsl_01].[dbo].style_size ss with (nolock), 
	 [EPICORSQL].[me_wsl_01].[dbo].color c with (nolock), 
	 [EPICORSQL].[me_wsl_01].[dbo].size_master sm with (nolock),
	 [EPICORSQL].[me_wsl_01].dbo.season se
WHERE st.style_id=s.style_id
AND s.style_color_id = sc.style_color_id 
AND s.style_size_id = ss.style_size_id
AND c.color_id = sc.color_id
AND sm.size_master_id = ss.size_master_id
AND st.season_id=se.season_id
--AND sc.reorder_flag=1 
--AND se.season_code in ('CO','KY')
----AND ss.style_id in (Select distinct style_id from InstockReport)




select t.sku_id, 
	   t.color_id,
	   t.size_master_id,
	   t.size_code,
	   t.color_code ColorCode,
	   t.extended_desc ExtendedColDesc,
	   s.* into #stylesku
from #tempsize t
join Style s with (nolock)
on t.style_id = s.style_id


-----------------------Set Periods----

DECLARE @D1 DateTime
SET @D1 = CONVERT(Date, GETDATE()-1) --Yesterday

Declare @year varchar(15)
Set @year= (Select merch_year from [EPICORSQL].[me_wsl_01].[dbo].[calendar_date] where calendar_date = @D1 )

DECLARE @WeekEndDate DateTime
SET @WeekEndDate = (SELECT MAX(calendar_date) FROM [EPICORSQL].[me_wsl_01].[dbo].[calendar_date] WHERE merch_week = 
      (SELECT  merch_week FROM [EPICORSQL].[me_wsl_01].[dbo].[calendar_date] WHERE calendar_date = @D1) and merch_year=@year)


Select * into #OnHand from (
SELECT i.sku_id, s.style_id,
sum(transaction_units) as OH_units, 
sum(transaction_cost)  as OH_Cost, 
sum(transaction_valuation_retail) as OH_Retail

FROM 
               [EPICORSQL].[me_wsl_01].[dbo].[ib_inventory] i with (nolock) 
              join [EPICORSQL].[me_wsl_01].[dbo].[calendar_date] c ON i.TRANSACTION_DATE <= c.CALENDAR_DATE
              join [EPICORSQL].me_wsl_01.dbo.sku s on i.sku_id = s.sku_id
              join  [EPICORSQL].me_wsl_01.dbo.location l with (nolock) on i.location_id=l.location_id
WHERE 
            c.CALENDAR_DATE = @D1 --'2026-02-26' -- change to current date / last day of period logic
            and i.INVENTORY_STATUS_ID in (1,2)
           and i.location_id not in ('79','80','81','82','83','84','85')
		   and i.sku_id in (select sku_id from #tempsize)
group by i.sku_id,style_id
)a;


----------------------Retail Selling Price
Select style_id,start_date,valuation_retail_price,price_status_id
 into #Retail from
 (Select style_id,start_date, valuation_retail_price, [price_status_id], Row_Number() over (partition by style_id order by ib_price_id desc) rowno
 from [EPICORSQL].me_wsl_01.dbo.ib_price with (nolock) where 
 ----(location_id  not in (78,110,111,118) or location_id is null) 
 location_id is NULL 
 and end_date is NULL
 and style_id in (select style_id from #tempsize))a where
 rowno=1;

 


 Select distinct style_id,start_date as promostartdate, promo 
 into #promo2
 from
 (select style_id, start_date, valuation_retail_price as promo, Row_Number() over (partition by style_id order by ib_price_id desc) rowno from [EPICORSQL].me_wsl_01.dbo.ib_price ib with (nolock)
 where temp_price_flag = 1 
 and convert(date,getdate()) <=end_date  
 and location_id is NULL
 and style_id in (select style_id from #tempsize)
 )a
 where rowno=1;

 
Select style_id,
        case when promo is Null then valuation_retail_price  ----If there is promo price use promo else retail
		else promo 
		end as Retail,
		case when promostartdate is NUll then start_date else promostartdate end as PriceDate,
		price_status_code as PriceStatus
 into #ReProStatus
 from 
 (Select r.style_id,r.valuation_retail_price,r.price_status_id, r.start_date,
 pp.price_status_code, p.promostartdate, p.promo
 from
 #Retail r 
 left join
 #promo2 p 
 on
 r.style_id =p.style_id
 left join 
 [EPICORSQL].me_wsl_01.dbo.price_status pp
 on r.price_status_id =pp.price_status_id 
 )a;

----Merchandise Hierachy File

select top 5 distinct
   s.Divisionlabel,
   s.Dept,
   s.SubDept,
   s.Class,
 --  s.colorcode, not used in the ssrs report
   s.ExtendedColDesc, 
--s.[style_id],
   s.[style_code],
   s.size_code,
   s.sku_id SKU,
   s.[long_desc],
   v.vendor_name as Vendor,
   b.attribute_set_label as Brand,
   s.season_code,
    case when oh.OH_Cost/NULLIF(oh.OH_Units,0) is not NULL then convert(Decimal(18,2),oh.OH_Cost/NULLIF(oh.OH_Units,0))
	   else sv.current_cost end as [Cost],
	--   sv.current_cost, 
	   sr.compare_at_retail as MSRP,
	   rps.Retail as SellingPrice,
	   rps.PriceStatus
From
#stylesku s with (nolock)
left JOIN
#onhand oh
on
s.sku_id=oh.sku_id
left JOIN
[EPICORSQL].[me_wsl_01].dbo.style_vendor sv
on
s.style_id=sv.style_id
Left JOIN
[EPICORSQL].[me_wsl_01].dbo.vendor v
on 
sv.vendor_id=v.vendor_id
left JOIN
[EPICORSQL].[me_wsl_01].dbo.style_retail sr
on
s.style_id =sr.style_id 
Left JOIN
Brand b
on
s.style_id=b.style_id
Left JOIN
#ReProStatus rps
on
s.style_id=rps.style_id
where sv.primary_vendor_flag =1  ---Added active vendor name
--and s.active_flag = 'Y'


drop table #tempsize
drop table #stylesku
drop table #OnHand
drop table #Retail
drop table #promo2
drop table #ReProStatus


END
