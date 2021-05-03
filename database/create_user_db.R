library(RSQLite)
library(dplyr)
library(tidyr)
library(stringr)
library(sf)
library(openxlsx)

# User data from Mike's databse
setwd("/Users/jeremyseeman/Desktop/SODA501")
conn <- dbConnect(SQLite(), "tweets.db")
raw_users <- dbGetQuery(conn, "SELECT * FROM users")
dbDisconnect(conn)


clean_state_abbr = function(v) { 
  tv = str_replace(str_to_upper(str_trim(v)), "\\.", "")
  if (nchar(tv) == 2) {
    tv
  } else {
    # multiple places specified in state
    for (cr in c("\\/", "\\&", " AND ", "\\|", " VIA ", "-") ) {
      tv = str_trim(str_split_fixed(tv, cr, 2)[, 1])
    }
    tv
  }
}


place_abbrs = data.frame(
  orig=c("ST ", "FT ", "MT ", "N ", "SO "),
  new=c("SAINT ", "FORT ", "MOUNT ", "NORTH ", "SOUTH ")
)

remove_areas = c(" METRO AREA$", 
                 " AREA$",
                 " SUBURBS$")

clean_place_name = function(v) {
  # standardize place name
  cv = str_replace(str_to_upper(str_trim(v)), "\\.", "")
  
  # expand abbrevations 
  for (abbr_ix in 1:dim(place_abbrs)[1]) {
    cv = str_replace(cv,
                     paste("^", place_abbrs[abbr_ix, "orig"], sep=""), 
                     place_abbrs[abbr_ix, "new"])
  }
  # remove generic specifiers
  for (ra in remove_areas) { 
    cv = str_replace(cv, ra, "")
  }
  cv
}

users = raw_users %>% bind_cols(
  data.frame(str_split_fixed(raw_users$location, ", ", n=2)) %>% 
    rename(city=X1, state=X2)
  ) %>% 
  mutate(place_name=clean_place_name(city),
         state_abbr=clean_state_abbr(state)) %>% select(
  user_id=id, location, place_name, state_abbr
)

# extract full place when embedded in state
state_splits = data.frame(str_split_fixed(users$state_abbr, ", ", 2)) %>% 
  rename(split_place=1, split_state=2)
is_state_split = data.frame(is_split=unlist(
  apply(state_splits, 1, function(z) { length(z) == 2 & nchar(z[2]) == 2 })
))

users = bind_cols(users, state_splits, is_state_split) %>% 
  mutate(place_name=ifelse(is_split, split_place, place_name),
         state_abbr=ifelse(is_split, split_state, state_abbr)) %>%
  select(user_id, location, place_name, state_abbr)


# CENSUS GEOCODES -----------------------------------------------------------

# Census Geocode source: https://www.census.gov/geographies/reference-files/2018/demo/popest/2018-fips.html
# State abbreviation source: https://www.ssa.gov/international/coc-docs/states.html
geocodes = read.xlsx("census_geocodes.xlsx", startRow=5)
state_abbrevs = read.csv("state_abbr.csv")

states = geocodes %>% 
  # select only state-level summaries
  filter(Summary.Level == "040") %>%
  mutate(state_name=str_to_upper(
           str_trim(`Area.Name.(including.legal/statistical.area.description)`)
         )) %>%
  select(state_fips=`State.Code.(FIPS)`,
         state_name) %>%
  left_join(state_abbrevs %>% 
              mutate(state_name=str_to_upper(str_trim(state_name))),
            by="state_name") %>%
  mutate(state_abbr=ifelse(state_fips == 44, "RI", state_abbr))

counties = geocodes %>%
  # select only county-level summaries 
  filter(Summary.Level == "050") %>%
  # concatenate state and county components 
  mutate(county_fips=paste(`State.Code.(FIPS)`, `County.Code.(FIPS)`, sep=""),
         county_name=str_replace(
           str_to_upper(
             str_trim(
               `Area.Name.(including.legal/statistical.area.description)`
             )
           ),
           " COUNTY", ""
         )) %>%
  select(state_fips=`State.Code.(FIPS)`, 
         county_fips, 
         county_name)

subds = geocodes %>%
  # select only subdivision summaries
  filter(Summary.Level == "061") %>%
  # split subdivision into proper name and type
  mutate(
    county_fips=paste(`State.Code.(FIPS)`, `County.Code.(FIPS)`, sep=""),
    subd_fips=paste(`State.Code.(FIPS)`, `County.Code.(FIPS)`, 
                    `County.Subdivision.Code.(FIPS)`, sep=""),
    subd_split=str_split(
      str_to_upper(
        str_trim(
          `Area.Name.(including.legal/statistical.area.description)`
        ),
      ), 
      " "
    ),
    subd_name=sapply(subd_split, function(z) {
      paste(head(z, -1), collapse=" ")
    }),
    subd_type=sapply(subd_split, function(z) {
      paste(tail(z, 1), collapse="")
    }),
    subd_full_name=paste(subd_name, subd_type)
  ) %>%
  select(state_fips=`State.Code.(FIPS)`, 
         county_fips, 
         subd_fips,
         subd_name,
         subd_type,
         subd_full_name)

places = geocodes %>%
  filter(Summary.Level == "162") %>%
  mutate(
    county_fips=paste(`State.Code.(FIPS)`, `County.Code.(FIPS)`, sep=""),
    place_fips=paste(`State.Code.(FIPS)`, `County.Code.(FIPS)`, 
                    `Place.Code.(FIPS)`, sep=""),
    place_split=str_split(
      str_to_upper(
        str_trim(
          `Area.Name.(including.legal/statistical.area.description)`
        ),
      ), 
      " "
    ),
    place_name=sapply(place_split, function(z) {
      paste(head(z, -1), collapse=" ")
    }),
    place_type=sapply(place_split, function(z) {
      paste(tail(z, 1), collapse="")
    }),
    place_full_name=paste(place_name, place_type)
  ) %>%
  select(state_fips=`State.Code.(FIPS)`, 
         county_fips, 
         place_fips,
         place_name,
         place_type,
         place_full_name)

# CROSSWALKS ------------------------------------------------------------------

# Federal city-state to ZIP code (includes unincorporated places)
# Source: http://federalgovernmentzipcodes.us/index.html
place2zip = read.csv("city2zipcode.csv") %>%
  # exclude PO boxes, military/non-civilian, and other special use ZIPs
  filter(ZipCodeType == "STANDARD",
         # exclude historical ZIPs
         Decommisioned == "false")  %>% 
  mutate(zip=str_pad(Zipcode, 5, pad="0"),
         # if place is Census-recognized as incoporated 
         is_acceptable=(LocationType %in% c("ACCEPTABLE", "PRIMARY")),
         # if place is primary place in ZIP code
         is_primary=(LocationType == "PRIMARY")) %>%
  select(zip,
         place_name=City,
         state_abbr=State,
         is_acceptable,
         is_primary)

# add primary place name by zip
place2zip = place2zip %>% 
  left_join(place2zip %>% 
              filter(is_primary==T) %>% 
              select(zip, primary_place_name=place_name),
            by="zip")

# ZIP code to county crosswalk
# Source: https://www.huduser.gov/portal/datasets/usps_crosswalk.html
zip2county = read.xlsx("zip2county_hud.xlsx") %>% 
  select(zip=ZIP, county_fips=COUNTY, ratio=TOT_RATIO) 

# construct primary county from pop ratios
primary_zip_counties = zip2county %>% group_by(zip) %>%
  summarise(primary_county_fips=county_fips[which.max(ratio)])

zip2county = zip2county %>%
  left_join(primary_zip_counties, by="zip") %>%
  mutate(is_primary=(county_fips == primary_county_fips))


# SPATIAL COVARIATES -------------------------------------------------------

# Hospitalizations data
# Source: https://beta.healthdata.gov/Hospital/COVID-19-Reported-Patient-Impact-and-Hospital-Capa/anag-cw7u
covid_hosp = read.csv("hosp.csv") 
hosps = covid_hosp %>% distinct(hospital_pk, .keep_all=TRUE) %>% 
  filter(geocoded_hospital_address != "") 

# geocoded hospital locations to county data
pt_geoms = lapply(
  str_extract_all(hosps$geocoded_hospital_address, "\\d+"),
  function(r) {
    st_point(x=c(as.numeric(paste("-", r[1], ".", r[2], sep="")),
                 as.numeric(paste(r[3], ".", r[4], sep=""))),
             dim="XY")
  }
)
pts = st_sf(
  hospital_pk = hosps$hospital_pk,
  city=hosps$city,
  state=hosps$state,
  geom=st_sfc(pt_geoms)
)
# Census 2019 county boundary shapefile
# Source: https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html
county_shp = st_read("cb_2019_us_county_20m")
st_crs(pts) <- st_crs(county_shp) # map Census CRS to geocoded hospitals
hosps = st_join(pts, county_shp, join=st_within) %>% 
  rename(county=NAME) %>% 
  select(hospital_pk, city, state, county)

# combine with original covid hospitalization data
covid_hosp_by_county = covid_hosp %>% 
  na_if(-999999) %>%
  inner_join(hosps, by="hospital_pk") %>%
  mutate(county=str_to_upper(county)) %>%
  group_by(county, collection_week) %>% 
  summarise(
    adult_hosp_confsus_covid=sum(total_adult_patients_hospitalized_confirmed_and_suspected_covid_7_day_sum),
    adult_hosp_conf_covid=sum(total_adult_patients_hospitalized_confirmed_covid_7_day_sum),
    ped_hosp_confsus_covid=sum(total_pediatric_patients_hospitalized_confirmed_and_suspected_covid_7_day_sum),
    ped_hosp_conf_covid=sum(total_pediatric_patients_hospitalized_confirmed_covid_7_day_sum),
    total_beds=sum(total_beds_7_day_avg * 7),
    total_inpatient_beds=sum(inpatient_beds_used_7_day_avg * 7),
    total_icu_beds=sum(total_icu_beds_7_day_avg * 7),
    n_hospitals_reporting=n()
)

# County Health Rankings (UW-Madison Epidemiology and Public Health Survey)
# Source: https://www.countyhealthrankings.org/resources/2020-chr-national-statistics

chr = read.csv("chr2020.csv", skip=1)
chr2 = chr %>%
  # ignore state-level summaries
  filter(`statecode` != 0 & `countycode` != 0) %>%
  mutate(
    state_fips=str_pad(`statecode`, 2, pad="0"),
    county_name=sapply(
      str_split(str_to_upper(str_trim(`county`)), " "),
      function(r) { paste(head(r, -1), collapse=" ") }
    ),
    county_fips=str_pad(`fipscode`, 5, pad="0"),
  ) %>%
  select(
    county_fips,
    county_name,
    state_fips,
    state_abbr=`state`,
    premature_death_num=`v001_rawvalue`,
    poor_fair_health_pct=`v002_rawvalue`,
    poor_physical_health_days_month_avg=`v036_rawvalue`,
    poor_mental_health_days_month_avg=`v042_rawvalue`,
    newborns_low_weight_pct=`v037_rawvalue`,
    adult_smoke_pct=`v009_rawvalue`,
    adult_obese_pct=`v011_rawvalue`,
    food_env_idx=`v133_rawvalue`, # scale of 0-10, 10 being best access
    physically_inactive_pct=`v070_rawvalue`,
    access_to_exercise_pct=`v132_rawvalue`,
    excess_drink_pct=`v049_rawvalue`,
    alcohol_impaired_driving_death_pct=`v134_rawvalue`,
    chlamydia_cases_per_100k=`v045_rawvalue`, 
    teen_births_per_1k=`v014_rawvalue`,
    uninsured_pct=`v085_rawvalue`,
    pop_per_primary_care_physician=`v004_other_data_1`,
    pop_per_mental_health_provider=`v062_other_data_1`,
    preventable_hospital_stays_per_100k=`v005_rawvalue`,
    medicare_flu_vax_pct=`v155_rawvalue`,
    high_school_grad_pct=`v021_rawvalue`,
    some_college_pct=`v069_rawvalue`,
    unemployed_pct=`v023_rawvalue`,
    children_poverty_pct=`v024_rawvalue`,
    inequality_idx_8020ratio=`v044_rawvalue`,
    social_associations_per_10k=`v140_rawvalue`,
    children_single_parent_pct=`v082_rawvalue`,
    violent_crime_per_100k=`v043_rawvalue`,
    injury_deaths_per_100k=`v135_rawvalue`,
    air_pollution_micrograms_per_m3=`v125_rawvalue`,
    drinking_water_violation=`v124_rawvalue`,
    high_housing_cost_pct=`v136_other_data_1`,
    overcrowding_pct=`v136_other_data_2`,
    no_plumbing_pct=`v136_other_data_3`,
    drive_alone_to_work_pct=`v067_rawvalue`,
    long_solo_commute_pct=`v137_rawvalue`
  )

# USER VIEW ------------------------------------------------------------------

view_def_dplyr = users %>% 
  left_join(place2zip %>% filter(is_primary == T),
            by=c("place_name", "state_abbr")) %>%
  left_join(zip2county %>% filter(is_primary == T),
            by="zip") %>%
  left_join(states, by="state_abbr") %>%
  left_join(places %>% select(state_fips, place_name, place_type), 
            by=c("state_fips", "place_name")) %>%
  left_join(counties %>% select(county_fips, county_name),
            by="county_fips") %>%
  left_join(subds %>% select(subd_name, subd_type, state_fips),
            by=c("state_fips"="state_fips", "place_name"="subd_name")) %>% 
  select(
    user_id,
    user_place_name=`place_name`,
    user_state_abbr=`state_abbr`,
    state_fips,
    state_name,
    zip,
    county_fips,
    county_name,
    place_type,
    subd_type
  ) %>% arrange(
    user_id, zip
  )

view_def = "
CREATE VIEW twitter_users_vw 
AS
  SELECT 
    tu.user_id,
    tu.place_name,
    tu.state_abbr,
    st.state_fips,
    st.state_name,
    p2z.zip,
    c2z.county_fips,
    cou.county_name,
    pl.place_type,
    sub.subd_type
  FROM twitter_users AS tu
  LEFT JOIN (SELECT * 
             FROM crosswalk_place2zip
             WHERE is_primary = TRUE) AS p2z 
  ON tu.place_name = p2z.place_name AND 
     tu.state_abbr = p2z.state_abbr
  LEFT JOIN (SELECT * 
             FROM crosswalk_zip2county
             WHERE is_primary = TRUE) AS c2z
  ON c2z.zip = p2z.zip
  LEFT JOIN census_states AS st
  ON tu.state_abbr = st.state_abbr
  LEFT JOIN (SELECT state_fips, place_name, place_type
             FROM census_places) AS pl
  ON st.state_fips = pl.state_fips AND
     tu.place_name = pl.place_name
  LEFT JOIN (SELECT county_name, county_fips
             FROM census_counties) AS cou
  ON cou.county_fips = c2z.county_fips
  LEFT JOIN (SELECT subd_name, subd_type, state_fips
             FROM census_subds) AS sub
  ON sub.state_fips = st.state_fips AND
     sub.subd_name = tu.place_name;
"

# USERS COUNTY CONSTRUCTION ------------------------------------------------


# categorical mode function
cat_mode = function(v) {
  names(which.max(table(v)))
}

# match users by primary place to ZIP code
users_by_place2zip_primary = users %>% 
  left_join(place2zip %>% filter(is_primary == T),
            by=c("place_name", "state_abbr")) %>%
  left_join(zip2county %>% filter(is_primary == T),
            by="zip") %>%
  left_join(states, by="state_abbr") %>%
  drop_na(county_fips) %>% 
  group_by(user_id, location, place_name, state_abbr, state_fips, state_name) %>% 
  summarise(county_fips=cat_mode(county_fips)) %>%
  ungroup %>%
  inner_join(counties %>% select(county_fips, county_name),
             by="county_fips") %>%
  mutate(join_key="place2zip_primary") %>%
  select(
    user_id,
    location,
    place_name,
    state_abbr,
    state_name,
    county_name,
    state_fips,
    county_fips,
    join_key
  )

# match remaining users by secondary place to ZIP code
users_by_place2zip_secondary = users %>% 
  left_join(users_by_place2zip_primary %>% select(user_id, join_key),
            by="user_id") %>%
  filter(is.na(join_key)) %>%
  left_join(place2zip %>% filter(is_primary == F),
            by=c("place_name", "state_abbr")) %>%
  left_join(zip2county %>% filter(is_primary == T),
            by="zip") %>%
  left_join(states, by="state_abbr") %>%
  drop_na(county_fips) %>% 
  group_by(user_id, location, place_name, state_abbr, state_fips, state_name) %>% 
  summarise(county_fips=cat_mode(county_fips)) %>%
  ungroup %>%
  inner_join(counties %>% select(county_fips, county_name),
             by="county_fips") %>%
  mutate(join_key="place2zip_secondary") %>%
  select(
    user_id,
    location,
    place_name,
    state_abbr,
    state_name,
    county_name,
    state_fips,
    county_fips,
    join_key
  )

users_complete = bind_rows(users_by_place2zip_primary,
                           users_by_place2zip_secondary)

# match remaining users by county name
users_by_county = users %>%
  left_join(users_complete %>% select(user_id, join_key),
            by="user_id") %>%
  filter(is.na(join_key)) %>%
  left_join(states, by="state_abbr") %>% 
  left_join(counties %>%
              mutate(county_full_name=paste(county_name, "COUNTY")),
            by=c("state_fips"="state_fips", "place_name"="county_full_name")) %>%
  drop_na(county_name) %>%
  mutate(join_key="county") %>%
  select(
    user_id,
    location,
    place_name,
    state_abbr,
    state_name,
    county_name,
    state_fips,
    county_fips,
    join_key
  )

users_complete = bind_rows(users_complete, 
                           users_by_county)

# match remaining users by Census subdivision designation
users_by_subd = users %>% 
  left_join(users_complete %>% select(user_id, join_key),
            by="user_id") %>%
  filter(is.na(join_key)) %>%
  left_join(states, by="state_abbr") %>%
  left_join(subds %>% select(subd_name, subd_type, state_fips, county_fips),
            by=c("state_fips"="state_fips", "place_name"="subd_name")) %>%
  drop_na(subd_type) %>%
  left_join(counties %>% select(county_fips, county_name),
            by="county_fips") %>%
  mutate(join_key="subd") %>%
  select(
    user_id,
    location,
    place_name,
    state_abbr,
    state_name,
    county_name,
    state_fips,
    county_fips,
    join_key
  )

users_complete = bind_rows(users_complete,
                           users_by_subd)

# match remaining users by Census subdivision full name
users_by_subd_full = users %>% 
  left_join(users_complete %>% select(user_id, join_key),
            by="user_id") %>%
  filter(is.na(join_key)) %>%
  left_join(states, by="state_abbr") %>%
  left_join(subds %>% select(subd_full_name, subd_type, state_fips, county_fips),
            by=c("state_fips"="state_fips", "place_name"="subd_full_name")) %>%
  drop_na(subd_type) %>%
  left_join(counties %>% select(county_fips, county_name),
            by="county_fips") %>%
  mutate(join_key="subd_full") %>%
  select(
    user_id,
    location,
    place_name,
    state_abbr,
    state_name,
    county_name,
    state_fips,
    county_fips,
    join_key
  )

users_complete = bind_rows(users_complete, 
                           users_by_subd_full)

remaining_places = users %>% 
  left_join(users_complete %>% select(user_id, join_key),
            by="user_id") %>%
  filter(is.na(join_key)) %>%
  group_by(place_name, state_abbr) %>% 
  summarise(n_users=n()) %>%
  arrange(desc(n_users))
  
# DATABASE CONSTRUCTION 
userdb = dbConnect(RSQLite::SQLite(), "users.db")
dbWriteTable(userdb, "twitter_users", users)
dbWriteTable(userdb, "twitter_user_counties", users_complete)
dbWriteTable(userdb, "census_states", states)
dbWriteTable(userdb, "census_counties", counties)
dbWriteTable(userdb, "census_subds", subds)
dbWriteTable(userdb, "census_places", places)
dbWriteTable(userdb, "crosswalk_place2zip", place2zip)
dbWriteTable(userdb, "crosswalk_zip2county", zip2county)
dbWriteTable(userdb, "spatial_covid_hosps_by_county", covid_hosp_by_county)
dbWriteTable(userdb, "spatial_health_demos_by_county", chr2)
dbExecute(userdb, view_def)
dbDisconnect(userdb)
