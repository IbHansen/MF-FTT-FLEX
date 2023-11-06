'Template for FTT Standalone in EViews 
close @all

wfcreate a 1980 2050
%cty = "GNB"
%data_year = "2024"
%solve_start = "2025"
%solve_end = "2050"

MODEL {%cty}

'-----------------------------------------------------------------------------------------
' Define your technology list here
'-----------------------------------------------------------------------------------------
string technologylist = "OIL SOLAR HYDRO"
string technologylist2 = technologylist
smpl @all
'-----------------------------------------------------------------------------------------
'DATA inputs
'-----------------------------------------------------------------------------------------
'Read global assumtions, country specific assumption and country specific policy from FTT assumption file
import C:\WBG\LocalITUtilities\FTT-ModelFlow\FTT_modelflow\models\data\FTTAssumptions.xlsx range=ForEviews!$A$1:$BV$210 byrow colhead=2 namepos=custom colheadnames=("Name","Description") na="NA" format=(D,175W) @freq A 1980 @smpl @all
'delete title and empty rows
delete country_specific_assumptions* 
delete country_specific_policy_options*
delete global_assumptions 
delete series* 

'Create additional series and initialised 
series CO2ELETOT = 0.0 'Total CO2 (tCO2)
series COST_AVERAGE = 0.0 ''Average costs (USD per Mwh) - to feed to electricity price 
series PGINVESTMENT = 0.0 'Total investment by power sector m 2020 USD
' Initialise Policy costs, F,  productions and penalties sensitivity and mulipliers starting values
for %a {technologylist}
	series PRODUCTION_{%a} = 0.0
	series COST_POLICY_{%a} = COST_{%a} 
	series PENALTY_SENSITIVITY_{%a} = 3.0
     series PENALTY_MULTIPLIER_{%a} = 3.0
	series PENALTY_MAX_{%a} = 0.0
	series PENALTY_MIN_{%a} = 0.0
	for %b {technologylist2}
		series  F_{%a}_{%b} = 0.0
	next
next


'-----------------------------------------------------------------------------------------
'The below section create model eqations and extend series based on technology list above
'-----------------------------------------------------------------------------------------
smpl %solve_start %solve_end 

string shareeq = ""
!ntech = @wcount(technologylist2)

for %a {technologylist}
	for %b {technologylist2}
 '1. Sigma square equation
		{%cty}.APPEND @identity  SIGMA_{%a}_{%b} = SQR(SIGMA_{%a}^2*SIGMA_{%b}^2) 
		'intialise sigma values
		series  SIGMA_{%a}_{%b} = 0.0

'2.  Preference equations between pairwise comparison between technology 
     		{%cty}.APPEND @identity F_{%a}_{%b} = ((1)/(1+EXP( (((COST_POLICY_{%a}-COST_POLICY_{%b}))/(SIGMA_{%a}_{%b})) )))
		'intialise share preference values
		series  F_{%a}_{%b} = 0.0
	next
next

'3. Diffusion rate (A) = K / (leadt time i x lifetime of tech j), K = Kappa time constant approx = 10 from Mercure paper 2015
for %a {technologylist}
	for %b {technologylist2}
		{%cty}.APPEND @identity  A_{%a}_{%b} = 10/(LEAD_{%a}*TAU_{%b}) 	
		'intialise sigma values
		series  A_{%a}_{%b} = 0.0
	next
next

'4. Share equations
for %a {technologylist}
	shareeq = "SHARE_"+%a+" = SHARE_"+%a+"(-1) + ("
	!nt = 0.0 
	for %b {technologylist2}
		!nt = !nt +1
		if  !nt >= !ntech then
			shareeq = shareeq + "  SHARE_"+%a+"*SHARE_"+%b+"*(F_"+%a+"_"+%b+"*A_"+%a+"_"+%b+" - F_"+%b+"_"+%a+"*A_"+%b+"_"+%a+") )" 
   	  	else
		     shareeq = shareeq + "  SHARE_"+%a+"*SHARE_"+%b+"*(F_"+%a+"_"+%b+"*A_"+%a+"_"+%b+" - F_"+%b+"_"+%a+"*A_"+%b+"_"+%a+") +" 
     		endif
	next
	{%cty}.APPEND @identity {shareeq}
next

'5. Total electricity demand - Exogenous  *****If integrating this with MFMod this can be replaced with electricity demand equation***

'6. Production = share x total demand (Gwh)
for %a {technologylist}
	{%cty}.APPEND @identity  PRODUCTION_{%a} = SHARE_{%a} * TOTALDEMAND
next 

'7. Total CO2  (tCO2) = production (Gwh) x CO2 coefficient (tCO2/Gwh)
string co2eq = ""
co2eq = "CO2ELETOT = "
!nt = 0.0 
for %a {technologylist}
	!nt = !nt+1 
	if  !nt >= !ntech then
   		co2eq = co2eq + " PRODUCTION_"+%a+"*CO2COEFF_"+%a
   	else
  	 	co2eq = co2eq + " PRODUCTION_"+%a+"*CO2COEFF_"+%a+" +"  
     	endif
next 
{%cty}.APPEND @identity {co2eq}

'8. Max penalty for when production limit is breached
for %a {technologylist}
	'not sure how to do inverse logit in Eviews so write it out as  exp(x)/(1+exp(x)) 
	{%cty}.APPEND @identity  PENALTY_MAX_{%a} =  PENALTY_MULTIPLIER_{%a} * COST_{%a} * EXP(PENALTY_SENSITIVITY_{%a}*(PRODUCTION_{%a} - PRODUCTION_MAX_{%a})) / (1+EXP(PENALTY_SENSITIVITY_{%a}*(PRODUCTION_{%a} - PRODUCTION_MAX_{%a})))
next 

'9. Min penalty for when production is below min
for %a {technologylist}
	'not sure how to do inverse logit in Eviews so write it out as  exp(x)/(1+exp(x)) 
	{%cty}.APPEND @identity  PENALTY_MIN_{%a} =  PENALTY_MULTIPLIER_{%a} * COST_{%a} * EXP(PENALTY_SENSITIVITY_{%a}*(PRODUCTION_MIN_{%a} - PRODUCTION_{%a})) / (1+EXP(PENALTY_SENSITIVITY_{%a}*(PRODUCTION_MIN_{%a} - PRODUCTION_{%a})))
next 

'10. Investment LCOE $/Mwh - apply learning rate  and investment subsidy (0.5 = 50% subsidy), note apply to both mean and std. *****to add diminising return to represent resources availibility***
for %a {technologylist}
	'Capital cost + learning
	{%cty}.APPEND @identity  CAPITAL_COST_{%a} = CAPITAL_COST_{%a}(-1) *(1-DLOG(ACCUMULATED_PRODUCTION_{%a})*LEARNING_{%a}) 
	{%cty}.APPEND @identity  SIGMA_CAP_{%a} = SIGMA_CAP_{%a}(-1) *(1-DLOG(ACCUMULATED_PRODUCTION_{%a})*LEARNING_{%a})  

	'Investment Subsidy e.g. 20% convert to $/Mwh
	{%cty}.APPEND @identity  CAPITAL_SUB_{%a} = CAPITAL_COST_{%a}*(-CAPITAL_SUBSIDY_{%a})
	{%cty}.APPEND @identity  SIGMA_CAP_SUB_{%a} = SIGMA_CAP_{%a} *(-CAPITAL_SUBSIDY_{%a})
	series CAPITAL_SUB_{%a} = 0.0
	series SIGMA_CAP_SUB_{%a} = 0.0
next 

'11. O&M LCOE $/Mwh - apply learning rate but no subsidies
for %a {technologylist}
	{%cty}.APPEND @identity  OM_COST_{%a} = OM_COST_{%a}(-1) *(1-DLOG(ACCUMULATED_PRODUCTION_{%a})*LEARNING_{%a})
	{%cty}.APPEND @identity  SIGMA_OM_{%a} = SIGMA_OM_{%a}(-1) *(1-DLOG(ACCUMULATED_PRODUCTION_{%a})*LEARNING_{%a})
next 

'12. Fuel LCOE $/Mwh - coal, oil and gas - grow with international price and subject to tax (e.g. 0.2 = 20%). Others technology constant  - exogenous. *****If integrating this with MFMod this can be replaced with commodity price variables***
	'Price without tax grow with international price
	{%cty}.APPEND @identity  FUEL_COST_COAL = FUEL_COST_COAL(-1) * (COAL_PRICE / COAL_PRICE(-1))
	{%cty}.APPEND @identity  FUEL_COST_OIL  = FUEL_COST_OIL(-1) * (OIL_PRICE / OIL_PRICE(-1))
	{%cty}.APPEND @identity  FUEL_COST_GAS   = FUEL_COST_GAS(-1) * (GAS_PRICE / GAS_PRICE(-1))

	{%cty}.APPEND @identity  SIGMA_FUEL_COAL = SIGMA_FUEL_COAL(-1) * (COAL_PRICE / COAL_PRICE(-1))
	{%cty}.APPEND @identity  SIGMA_FUEL_OIL  = SIGMA_FUEL_OIL(-1) * (OIL_PRICE / OIL_PRICE(-1))
	{%cty}.APPEND @identity  SIGMA_FUEL_GAS   = SIGMA_FUEL_GAS(-1) * (GAS_PRICE / GAS_PRICE(-1))

	'Fuel tax e.g. 20% = 0.2 - convert to $/Mwh
	for %a {technologylist}
  		{%cty}.APPEND @identity FUEL_TAX_LEVEL_{%a} = FUEL_COST_{%a} *FUEL_TAX_{%a}
  		{%cty}.APPEND @identity SIGMA_FUEL_TAX_{%a} = SIGMA_FUEL_{%a} *FUEL_TAX_{%a}
		series FUEL_TAXLEVEL_{%a} = 0.0
		series SIGMA_FUEL_TAX_{%a} = 0.0
	next

'13. Carbon tax to be applied to fossile fuel, tax rate USD per tCO2 x CO2 cofficient tCO2 per Gwh  this give us USD per GWh --> divide this by 1000 to get $/Mwh  i.e. our LCOE unit. 
'Fuel coverage can be between 0-1 i.e. 1 = fully tax, 0.5 reduced tax rate 50%, 0 = exempt
for %a {technologylist}
  {%cty}.APPEND @identity CARBON_TAX_{%a} = CARBON_TAX_RATE * CO2COEFF_{%a} *0.001*FUEL_COVERAGE_{%a}
next

'14. Total costs $/Mwh - including learning rate, investment subsidy, fuel tax and carbon tax but excludes min and max penalties - this will be used to feed in to electricity price
for %a {technologylist}
	{%cty}.APPEND @identity  COST_{%a} = CAPITAL_COST_{%a} +  CAPITAL_SUB_{%a} + OM_COST_{%a} +  FUEL_COST_{%a}  + FUEL_TAX_LEVEL_{%a} + CARBON_TAX_{%a} 'mean
	{%cty}.APPEND @identity  SIGMA_{%a} = SIGMA_CAP_{%a}  + SIGMA_CAP_SUB_{%a} + SIGMA_OM_{%a} +  SIGMA_FUEL_{%a}  +   SIGMA_FUEL_TAX_{%a} 'std
next 

'15. Policy costs $/Mwh  = costs including  max and min penalties - this will feed in share equation
for %a {technologylist}
	{%cty}.APPEND @identity  COST_POLICY_{%a} = COST_{%a} + PENALTY_MAX_{%a} - PENALTY_MIN_{%a} 
next 

'16. Average costs to feed to electricity price (excluding penalitiesand carbon tax but can be changed) $/Mwh  *****If integrating this with MFMod this can be used to feedback to electricity price variable***
string averagecost = ""
averagecost = "COST_AVERAGE = ("
!nt = 0.0 
for %a {technologylist}
	!nt = !nt+1 
	if  !nt >= !ntech then
   		averagecost = averagecost + " COST_"+%a+"*SHARE_"+%a+")"
   	else
  	 	averagecost = averagecost + " COST_"+%a+"*SHARE_"+%a+" +"  
     	endif
next 
{%cty}.APPEND @identity {averagecost}


'17. Total carbon tax revenues m USD to feed back to fiscal balance -- need to be converted to m LCU outside this routine
string totalcarbontaxrev = ""
totalcarbontaxrev = "TOTALCTREV = ("
!nt = 0.0 
for %a {technologylist}
	!nt = !nt+1 
	if  !nt >= !ntech then
   		totalcarbontaxrev = totalcarbontaxrev + " CARBON_TAX_RATE * CO2COEFF_"+%a+"*FUEL_COVERAGE_"+%a+" * PRODUCTION_"+%a+"*0.000001)" 'carbon tax (USD/tCO2)* co2 coefficients (tCO2/Gwh) * fuel coverage * production (Gwh)* 0.000001 (divided by 1m = m USD)
   	else
  	 	totalcarbontaxrev = totalcarbontaxrev + " CARBON_TAX_RATE * CO2COEFF_"+%a+"*FUEL_COVERAGE_"+%a+" * PRODUCTION_"+%a+"*0.000001 +"  
     	endif
next 
{%cty}.APPEND @identity {totalcarbontaxrev}

'18. Total subsidy expenditure  m USD to feed back to fiscal balance -- need to be converted to m LCU outside this routine
string totalsubsidyexpenditure = ""
totalsubsidyexpenditure = "TOTALSUBEXP = ("
!nt = 0.0 
for %a {technologylist}
	!nt = !nt+1 
	if  !nt >= !ntech then
   		totalsubsidyexpenditure = totalsubsidyexpenditure + " CAPITAL_SUBSIDY_"+%a+"*(CAPITAL_COST_"+%a+ ") * 1000 * PRODUCTION_"+%a+"*0.000001)"  'subsidy (%) * (capital_cost ) (USD per MWh) * 1000 = USD per GWh * Production (GWh)  = USD * 0.000001 = m USD
   	else
  	 	totalsubsidyexpenditure = totalsubsidyexpenditure + " CAPITAL_SUBSIDY_"+%a+"*(CAPITAL_COST_"+%a+") * 1000  * PRODUCTION_"+%a+"*0.000001 +" 
     	endif
next 
{%cty}.APPEND @identity {totalsubsidyexpenditure}

'19. Fuel tax revenues m USD to feed back to fiscal balance -- need to be converted to m LCU outside this routine
string totalfueltaxrevenues = ""
totalfueltaxrevenues = "TOTALFTREV = ("
!nt = 0.0 
for %a {technologylist}
	!nt = !nt+1 
	if  !nt >= !ntech then
   		totalfueltaxrevenues = totalfueltaxrevenues + " FUEL_TAX_"+%a+"* FUEL_COST_"+%a+"* 1000  * PRODUCTION_"+%a+"*0.000001)"  'Fuel tax (%) * fuel_cost (USD per MWh) * 1000 = USD per GWh * production (Gwh) = USD * 0.000001 = m USD
   	else
  	 	totalfueltaxrevenues = totalfueltaxrevenues + " FUEL_TAX_"+%a+"* FUEL_COST_"+%a+"* 1000  * PRODUCTION_"+%a+"*0.000001 +" 
     	endif
next 
{%cty}.APPEND @identity {totalfueltaxrevenues}

'20. Total investment
string totalinvestmentreq = ""
totalinvestmentreq = "PGINVESTMENT = ("
!nt = 0.0 
for %a {technologylist}
	!nt = !nt+1 
	if  !nt >= !ntech then
   		totalinvestmentreq = totalinvestmentreq + " CAPITAL_COST_"+%a+"* 1000  * PRODUCTION_"+%a+"*0.000001)"  '(capital_cost) (USD per MWh) * 1000 = USD per GWh * Production (GWh)  = USD * 0.000001 = m USD
   	else
  	 	totalinvestmentreq = totalinvestmentreq + " CAPITAL_COST_"+%a+"* 1000  * PRODUCTION_"+%a+"*0.000001 +" 
     	endif
next 
{%cty}.APPEND @identity {totalinvestmentreq}

'-----------------------------------------------------------------------------------------
' SOLVE FOR SOLUTION
'-----------------------------------------------------------------------------------------
smpl %solve_start  %solve_end 
string stochs={%cty}.@stochastic
{%cty}.addassign(i,c) @stochastic
{%cty}.addinit(v=n) @stochastic

smpl %solve_start  %solve_end 
{%cty}.scenario "baseline" 'scenario name
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)


'----------------------------------------------------------------------------------------
' Test 1: Simple carbon tax scenario 
'----------------------------------------------------------------------------------------
{%cty}.scenario(n,a=2,i="Baseline",c) "CT30USD"
{%cty}.scenario "CT30USD"

smpl @all
series CARBON_TAX_RATE_2 = 0.0 
smpl 2025 2050
CARBON_TAX_RATE_2 = 30.00

'Solve model to 2050 with the carbon price $20
smpl %solve_start  %solve_end 
{%cty}.override CARBON_TAX_RATE 
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

'----------------------------------------------------------------------------------------
' Test 2: Simple solar subsidy scenario 
'----------------------------------------------------------------------------------------
{%cty}.scenario(n,a=3,i="Baseline",c) "SOLARSUB"
{%cty}.scenario "SOLARSUB"

smpl @all
series CAPITAL_SUBSIDY_SOLAR_3 = 0.0 
smpl 2025 2030
CAPITAL_SUBSIDY_SOLAR_3=  0.20

'Solve model to 2050 with the 30% solar subsidy
smpl %solve_start  %solve_end 
{%cty}.override CAPITAL_SUBSIDY_SOLAR 
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

'----------------------------------------------------------------------------------------
' Test 3:  Simple fuel tax scenario 
'----------------------------------------------------------------------------------------
{%cty}.scenario(n,a=4,i="Baseline",c) "TAXOIL"
{%cty}.scenario "TAXOIL"

smpl @all
series FUEL_TAX_OIL_4 = 0.0 
smpl 2025 2050
FUEL_TAX_OIL_4 =  0.25

'Solve model to 2050 with the 25% tax on oil
smpl %solve_start  %solve_end 
{%cty}.override FUEL_TAX_OIL
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

'----------------------------------------------------------------------------------------
' Test 4:  Limited lifetime of oil
'---------------------------------------------------------------------------------------
{%cty}.scenario(n,a=5,i="Baseline",c) "LIMITOIL"
{%cty}.scenario "LIMITOIL"

smpl @all
series TAU_OIL_5 = TAU_OIL
smpl 2025 2050
TAU_OIL_5  =  15

'Solve model to 2050 with the limit lifetime on oil from 40 years to 15years
smpl %solve_start  %solve_end 
{%cty}.override TAU_OIL
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

'----------------------------------------------------------------------------------------
' Test 5:  Deregulation reducing solar lead time
'---------------------------------------------------------------------------------------
{%cty}.scenario(n,a=6,i="Baseline",c) "SPEEDSOLAR"
{%cty}.scenario "SPEEDSOLAR"

smpl @all
series LEAD_SOLAR_6 = LEAD_SOLAR
smpl 2025 2050
LEAD_SOLAR_6 =  1

'Solve model to 2050 with the lead time solar speeding up from 1.5years to 1 year
smpl %solve_start  %solve_end 
{%cty}.override LEAD_SOLAR
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

'----------------------------------------------------------------------------------------
' Test 5:  Combined all policies
'---------------------------------------------------------------------------------------
{%cty}.scenario(n,a=7,i="Baseline",c) "ALL"
{%cty}.scenario "ALL"

smpl @all
series CARBON_TAX_RATE_7 = 0.0 
series CAPITAL_SUBSIDY_SOLAR_7 = 0.0 
series FUEL_TAX_OIL_7 = 0.0 
series TAU_OIL_7 = TAU_OIL
series LEAD_SOLAR_7 = LEAD_SOLAR

smpl 2025 2050
CARBON_TAX_RATE_7 = 30.00
FUEL_TAX_OIL_7 =  0.25
TAU_OIL_7 =  15
LEAD_SOLAR_7 = 1
smpl 2025 2030
CAPITAL_SUBSIDY_SOLAR_7=  0.20

'Solve model to 2050 with all policies
smpl %solve_start  %solve_end 
{%cty}.override CARBON_TAX_RATE CAPITAL_SUBSIDY_SOLAR FUEL_TAX_OIL TAU_OIL  LEAD_SOLAR
{%cty}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

'------------------------------------------------------------------------------------------------------------
'Plot results
smpl 2025 2050
'---------------------------------------------------------
'CO2
delete(noerr) _CO2 
graph _CO2 (CO2ELETOT_2/CO2ELETOT_0-1.0)*100 (CO2ELETOT_3/CO2ELETOT_0-1.0)*100 (CO2ELETOT_4/CO2ELETOT_0-1.0)*100 (CO2ELETOT_5/CO2ELETOT_0-1.0)*100 (CO2ELETOT_6/CO2ELETOT_0-1.0)*100 (CO2ELETOT_7/CO2ELETOT_0-1.0)*100 
'add series labels
_CO2.name(1) Carbon tax  (30USD/tCO2)
_CO2.name(2) Solar subsidy (20pc) for 5 years
_CO2.name(3) Oil fuel tax (25pc)
_CO2.name(4) Limit lifetime of oil from 40 to 15 years
_CO2.name(5) Reduce solar lead time from 1.5 to 1 years
_CO2.name(6) ALL POLICIES

'add title
_CO2.addtext(.71,-0.7,font(+b,16)) CO2 Emissions from the power sector in GNB 
_CO2.addtext(-.44, -.25,font(+i,10)) Percent change from baseline 
_CO2.axis(l) range(minmax)
_CO2.datelabel format("YYYY")
_CO2.legend columns(2)
show _CO2
'---------------------------------------------------------
'Investment requirement
delete(noerr) _INV 
graph _INV PGINVESTMENT_2-PGINVESTMENT_0 PGINVESTMENT_3-PGINVESTMENT_0 PGINVESTMENT_4-PGINVESTMENT_0 PGINVESTMENT_5-PGINVESTMENT_0 PGINVESTMENT_6-PGINVESTMENT_0 PGINVESTMENT_7-PGINVESTMENT_0
'add series labels
_INV.name(1) Carbon tax  (30USD/tCO2)
_INV.name(2) Solar subsidy (20pc) for 5 years
_INV.name(3) Oil fuel tax (25pc)
_INV.name(4) Limit lifetime of oil from 40 to 15 years
_INV.name(5) Reduce solar lead time from 1.5 to 1 years
_INV.name(6) ALL POLICIES

'add title
_INV.addtext(.71,-0.7,font(+b,16)) Additioanl PG Investment from baseline
_INV.addtext(-.44, -.25,font(+i,10)) m USD 2020 price
_INV.axis(l) range(minmax)
_INV.datelabel format("YYYY")
_INV.legend columns(2)
show _INV
'---------------------------------------------------------
'Electricity price
delete(noerr) _PRICE 
graph _PRICE (COST_AVERAGE_2/COST_AVERAGE_0-1.0)*100 (COST_AVERAGE_3/COST_AVERAGE_0-1.0)*100 (COST_AVERAGE_4/COST_AVERAGE_0-1.0)*100 (COST_AVERAGE_5/COST_AVERAGE_0-1.0)*100 (COST_AVERAGE_6/COST_AVERAGE_0-1.0)*100 (COST_AVERAGE_7/COST_AVERAGE_0-1.0)*100 
'add series labels
_PRICE.name(1) Carbon tax  (30USD/tCO2)
_PRICE.name(2) Solar subsidy (20pc) for 5 years
_PRICE.name(3) Oil fuel tax (25pc)
_PRICE.name(4) Limit lifetime of oil from 40 to 15 years
_PRICE.name(5) Reduce solar lead time from 1.5 to 1 years
_PRICE.name(6) ALL POLICIES

'add title
_PRICE.addtext(.71,-0.7,font(+b,16)) Electricity price in GNB
_PRICE.addtext(-.44, -.25,font(+i,10)) Percent change from baseline 
_PRICE.axis(l) range(minmax)
_PRICE.datelabel format("YYYY")
_PRICE.legend columns(2)
show _PRICE
'---------------------------------------------------------
'Fiscal implication in the combined scneario
delete(noerr) _Fiscal
graph _Fiscal TOTALFTREV_7 TOTALSUBEXP_7 TOTALCTREV_7 (TOTALFTREV_7+TOTALCTREV_7-TOTALSUBEXP_7)
'add series labels
_fiscal.bar
_Fiscal.name(1) Revelues from fuel tax on oil
_Fiscal.name(2) Subsidies spending on solar 
_Fiscal.name(3) Carbon tax revenues
_Fiscal.name(4) Net balance 

'add title
_Fiscal.addtext(.71,-0.7,font(+b,16)) Fiscal implication in the combined policy scneairo
_Fiscal.addtext(-.44, -.25,font(+i,10)) m USD 2020
_Fiscal.axis(l) range(minmax)
_Fiscal.datelabel format("YYYY")
_Fiscal.legend columns(2)
_fiscal.setelem(4) linepattern(DASH6)
show _Fiscal
'---------------------------------------------------------
'PG Share combined scenarios
smpl 2025 2050
delete(noerr) _ShareComb
graph _ShareComb SHARE_OIL_7 SHARE_SOLAR_7 SHARE_HYDRO_7 

'add series labels
_ShareComb.area(s)
_ShareComb.name(1) OIL
_ShareComb.name(2) SOLAR
_ShareComb.name(3) HYDRO

'add title
_ShareComb.addtext(.71,-0.7,font(+b,16)) GNB power generation mix in the combined policies scenario
_ShareComb.axis(l) range(0,1)
_ShareComb.datelabel format("YYYY")

show _ShareComb
'---------------------------------------------------------
'PG Share baseline
smpl 2025 2050
delete(noerr) _ShareBAU
graph _ShareBAU SHARE_OIL_0 SHARE_SOLAR_0 SHARE_HYDRO_0

'add series labels
_ShareBAU.area(s)
_ShareBAU.name(1) OIL
_ShareBAU.name(2) SOLAR
_ShareBAU.name(3) HYDRO

'add title
_ShareBAU.addtext(.71,-0.7,font(+b,16)) GNB power generation mix in the baseline
_ShareBAU.axis(l) range(0,1)
_ShareBAU.datelabel format("YYYY")

show _ShareBAU
'---------------------------------------------------------
smpl 2025 2050
delete(noerr) _LCOE
graph _LCOE COST_Solar_0 COST_Oil_0 COST_Solar_7 COST_Oil_7

'add series labels
_LCOE.name(1) LCOE Solar BAU
_LCOE.name(2) LCOE Oil BAU
_LCOE.name(3) LCOE Solar Combined Policies
_LCOE.name(4) LCOE Oil Combined Policies

'add title
_LCOE.addtext(0.0,-0.7,font(+b,16)) LCOE comparison between baseline and combined policy scenairo
_LCOE.addtext(-.44, -.25,font(+i,10)) USD/MWh
_LCOE.legend columns(2)
_LCOE.datelabel format("YYYY")
_LCOE.setelem(1) linecolor(@rgb(0,128,192))
_LCOE.setelem(3)  linecolor(@rgb(0,128,192))
_LCOE.setelem(2) linecolor(@rgb(128,0,0))
_LCOE.setelem(4) linecolor(@rgb(128,0,0))
_LCOE.options linepat
_LCOE.setelem(1) linepattern(DASH6)
_LCOE.setelem(2) linepattern(DASH6) 
_LCOE.setelem(3) linepattern(SOLID)
_LCOE.setelem(4) linepattern(SOLID) 

show _LCOE
'---------------------------------------------------------
'Electricity demand
smpl 2020 2050
delete(noerr) _ELEC
graph _ELEC TOTALDEMAND

'add title
_ELEC.addtext(.71,-0.7,font(+b,16)) GNB Total Electricity Demand Projections
_ELEC.addtext(-.44, -.25,font(+i,10)) GWh
_ELEC.datelabel format("YYYY")

show _ELEC
