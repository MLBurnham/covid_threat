#Spatial Data Compile
#SODA 501 FINAL PROJECT

library(readstata13)
library(readxl)
library(stringr)
library(tidyverse)
library(ggplot2)

set.seed(1234)

#covid cases and deaths
data_cases <- read_excel("covid_confirmed_usafacts_2_17_21.xlsx", sheet="covid_confirmed_usafacts")
data_cases<-data_cases %>%
  select(-County, -State, -StateFIPS)%>%
  rename_with( ~ paste("cases", .x, sep = "_"))%>%
  rename(geoid=cases_countyFIPS)%>%
  subset(geoid != 0)

data_deaths <- read_excel("covid_deaths_usafacts_2_17_21.xlsx", sheet="covid_deaths_usafacts")
data_deaths<-data_deaths %>%
  select(-County, -State, -StateFIPS)%>%
  rename_with( ~ paste("deaths", .x, sep = "_"))%>%
  rename(geoid=deaths_countyFIPS)%>%
  subset(geoid != 0)

#age composition (2014-2018)
ACS0<-read_excel("ACS0.xlsx", sheet="1")%>%
  select(GEO_ID, S0101_C02_030E)%>%
  rename(p_65_up=S0101_C02_030E)%>%
  rename(geoid=GEO_ID)
ACS0$geoid <- as.numeric(str_sub(ACS0$geoid,-5,-1))

#unemployment, median income, %poverty (2014-2018)
ACS1<-read_excel("ACS1.xlsx", sheet="1")%>%
  select(DP03_0009PE, DP03_0062E, DP03_0128PE, GEO_ID)%>%
  rename(geoid=GEO_ID)%>%
  rename(unemp_rate=DP03_0009PE)%>%
  rename(med_inc=DP03_0062E)%>%
  rename(ppov=DP03_0128PE)
ACS1$geoid <- as.numeric(str_sub(ACS1$geoid,-5,-1))

#Racial composition and total population (2014-2018)
ACS2<-read_excel("ACS2.xlsx", sheet="1")%>%
  select(B03002_001E, B03002_003E, B03002_004E, B03002_012E,B03002_006E, GEO_ID)%>%
  rename(geoid=GEO_ID)%>%
  rename(total_pop=B03002_001E)%>%
  rename(nhw=B03002_003E)%>%
  rename(nhb=B03002_004E)%>%
  rename(hisp=B03002_012E)%>%
  rename(asian=B03002_006E)
ACS2$geoid <- as.numeric(str_sub(ACS2$geoid,-5,-1))

#Educational attainment (2014-2018)
ACS3<-read_excel("ACS3.xlsx", sheet="1")%>%
  select(DP02_0066PE, DP02_0067PE, GEO_ID)%>%
  rename(geoid=GEO_ID)%>%
  rename(phs_grad=DP02_0066PE)%>%
  rename(pbach_grad=DP02_0067PE)
ACS3$geoid <- as.numeric(str_sub(ACS3$geoid,-5,-1))

#land area (2010)
census_2010_1<-read_excel("ACS4.xlsx", sheet="1")%>%
  select(geoid, SUBHD0303)%>%
  rename(landarea2010=SUBHD0303)%>%
  subset(geoid > 100)

#percent urban (2010)
census_2010_2<-read_excel("ACS5.xlsx", sheet="1")%>%
  select(STATE, COUNTY, POPPCT_URBAN)
census_2010_2$geoid<-as.numeric(census_2010_2$STATE)*1000+as.numeric(census_2010_2$COUNTY)

#presidential election results, 2000-2016
data_elections<-read.csv("countypres_2000-2016.csv")%>%
  subset(year==2016)%>%
  select(FIPS, party, candidatevotes, totalvotes)
data_elections<-reshape(data_elections, idvar = "FIPS", timevar = "party", direction = "wide")%>%
  select(FIPS, candidatevotes.democrat, totalvotes.democrat, candidatevotes.republican)%>%
  rename(dem_votes_2016=candidatevotes.democrat)%>%
  rename(rep_votes_2016=candidatevotes.republican)%>%
  rename(tot_votes_2016=totalvotes.democrat)%>%
  rename(geoid=FIPS)

#merging everything
merged_data<-data_cases%>%
  full_join(data_deaths, by = "geoid")%>%
  full_join(ACS0, by = "geoid")%>%
  full_join(ACS1, by = "geoid")%>%
  full_join(ACS2, by = "geoid")%>%
  full_join(ACS3, by = "geoid")%>%
  full_join(census_2010_1, by = "geoid")%>%
  full_join(census_2010_2, by = "geoid")%>%
  full_join(data_elections, by = "geoid")
  
write.csv(merged_data, file = 'merged_data.csv')

