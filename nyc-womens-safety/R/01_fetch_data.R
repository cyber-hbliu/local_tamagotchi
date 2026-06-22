# =============================================================================
# 01_fetch_data.R  --  Download & cache every raw layer (NYC Open Data + Census)
# Run after sourcing 00_setup.R. All pulls are filtered server-side and cached.
# =============================================================================

# ---- Public-space premises (outdoor + transportation), per the study design --
PREM_OUTDOOR <- c("STREET","PARK/PLAYGROUND","HIGHWAY/PARKWAY","BRIDGE","TUNNEL",
                  "OPEN AREAS (OPEN LOTS)","CONSTRUCTION SITE",
                  "PARKING LOT/GARAGE (PUBLIC)","MARINA/PIER")
PREM_TRANSIT <- c("TRANSIT - NYC SUBWAY","BUS (NYC TRANSIT)","BUS STOP","BUS TERMINAL",
                  "TRANSIT FACILITY (OTHER)","FERRY/FERRY TERMINAL","TRAMWAY",
                  "TAXI (LIVERY LICENSED)","TAXI (YELLOW LICENSED)","TAXI/LIVERY (UNLICENSED)",
                  "BUS (OTHER)")
PREM_PUBLIC  <- c(PREM_OUTDOOR, PREM_TRANSIT)

sq_list <- function(x) paste0("(", paste0("'", x, "'", collapse = ","), ")")

# ---- 1. NYPD complaints: public premises, female & male victims, 2020-2022 ----
fetch_crime <- function(refresh = FALSE) {
  where <- sprintf(
    "cmplnt_fr_dt between '%sT00:00:00' and '%sT23:59:59' and vic_sex in ('F','M') and prem_typ_desc in %s",
    CFG$date_start, CFG$date_end, sq_list(PREM_PUBLIC))
  socrata_get(CFG$ds$crime$domain, CFG$ds$crime$id,
    query = list(
      `$select` = paste("cmplnt_num,cmplnt_fr_dt,cmplnt_fr_tm,vic_sex,susp_sex,",
                        "ky_cd,ofns_desc,law_cat_cd,prem_typ_desc,boro_nm,latitude,longitude"),
      `$where`  = where),
    cache = file.path(DIR_RAW, "crime_public.csv"), refresh = refresh)
}

# ---- 2. 311 broken streetlight complaints (density + repair timing) ----------
fetch_lights <- function(refresh = FALSE) {
  where <- sprintf("complaint_type='Street Light Condition' and created_date between '%sT00:00:00' and '%sT23:59:59'",
                   CFG$date_start, CFG$date_end)
  socrata_get(CFG$ds$light_311$domain, CFG$ds$light_311$id,
    query = list(
      `$select` = "unique_key,created_date,closed_date,status,descriptor,latitude,longitude",
      `$where`  = where),
    cache = file.path(DIR_RAW, "lights_311.csv"), refresh = refresh)
}

# ---- 3. Street pavement ratings (.geojson -> sf), centroids per segment ------
fetch_pavement <- function(refresh = FALSE) {
  cache <- file.path(DIR_RAW, "pavement.gpkg")
  if (file.exists(cache) && !refresh) { message("  [cache] pavement.gpkg"); return(st_read(cache, quiet = TRUE)) }
  # discover the rating column
  cols <- names(jsonlite::fromJSON(sprintf("https://%s/resource/%s.json?$limit=1",
                                           CFG$ds$pavement$domain, CFG$ds$pavement$id)))
  rate_col <- intersect(c("systemrating","rating_word","ratingword","rating","status"), tolower(cols))[1]
  url <- sprintf("https://%s/resource/%s.geojson?$limit=600000&$select=%s,the_geom",
                 CFG$ds$pavement$domain, CFG$ds$pavement$id, rate_col)
  pv <- st_read(url, quiet = TRUE)
  names(pv)[names(pv) == rate_col] <- "rating_word"
  # map word ratings -> 1..10 midpoints (Good 9 / Fair 5.5 / Poor 2)
  pv <- pv %>% mutate(
    rating_num = dplyr::case_when(
      str_detect(toupper(rating_word), "GOOD") ~ 9,
      str_detect(toupper(rating_word), "FAIR") ~ 5.5,
      str_detect(toupper(rating_word), "POOR") ~ 2,
      TRUE ~ suppressWarnings(as.numeric(rating_word)))) %>%
    filter(!is.na(rating_num)) %>%
    st_transform(CFG$crs_proj) %>% st_centroid()
  st_write(pv, cache, quiet = TRUE, delete_dsn = TRUE)
  pv
}

# ---- 4. PLUTO vacant land parcels (land use 11) -----------------------------
fetch_vacant <- function(refresh = FALSE) {
  socrata_get(CFG$ds$pluto$domain, CFG$ds$pluto$id,
    query = list(`$select` = "bbl,borough,landuse,lotarea,latitude,longitude",
                 `$where`  = "landuse='11'"),
    cache = file.path(DIR_RAW, "vacant.csv"), refresh = refresh)
}

# ---- 5. Subway stations (data.ny.gov) ---------------------------------------
fetch_subway <- function(refresh = FALSE) {
  df <- socrata_get(CFG$ds$subway$domain, CFG$ds$subway$id, query = list(),
                    cache = file.path(DIR_RAW, "subway.csv"), refresh = refresh)
  # detect lat/lon columns (gtfs_latitude/longitude on this dataset)
  latc <- intersect(c("gtfs_latitude","latitude","stop_lat"), names(df))[1]
  lonc <- intersect(c("gtfs_longitude","longitude","stop_lon"), names(df))[1]
  df %>% rename(latitude = all_of(latc), longitude = all_of(lonc))
}

# ---- 6. NYC Facilities Database ---------------------------------------------
fetch_facilities <- function(refresh = FALSE) {
  socrata_get(CFG$ds$facilities$domain, CFG$ds$facilities$id,
    query = list(`$select` = "facname,facgroup,facsubgrp,factype,latitude,longitude"),
    cache = file.path(DIR_RAW, "facilities.csv"), refresh = refresh)
}

# ---- 7. Women's / domestic-violence resources -------------------------------
# HRA DV Partners may lack coordinates; fall back to the 5 NYC Family Justice Centers.
FJC <- tibble::tribble(
  ~name,                 ~latitude, ~longitude,
  "FJC Manhattan",        40.7128,  -74.0016,
  "FJC Brooklyn",         40.6904,  -73.9857,
  "FJC Bronx",            40.8268,  -73.9209,
  "FJC Queens",           40.7060,  -73.8068,
  "FJC Staten Island",    40.6376,  -74.0760)
fetch_dv <- function(refresh = FALSE) {
  df <- tryCatch(socrata_get(CFG$ds$dv$domain, CFG$ds$dv$id, query = list(),
                             cache = file.path(DIR_RAW, "dv.csv"), refresh = refresh),
                 error = function(e) NULL)
  latc <- if (!is.null(df)) intersect(c("latitude","lat"), names(df))[1] else NA
  if (!is.null(df) && !is.na(latc) && sum(!is.na(df[[latc]])) > 5) {
    lonc <- intersect(c("longitude","lon","lng"), names(df))[1]
    return(df %>% rename(latitude = all_of(latc), longitude = all_of(lonc)))
  }
  message("  [dv] no usable coordinates; using Family Justice Centers as women's-resource proxy")
  FJC
}

message("01_fetch_data.R loaded (call fetch_* functions)")
