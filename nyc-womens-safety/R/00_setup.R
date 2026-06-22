# =============================================================================
# 00_setup.R  --  Packages, configuration, and data-access helpers
# Project: Infrastructure & Women's Public Safety in NYC (rebuild)
# =============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(lubridate)
  library(jsonlite)
  library(ggplot2)
  library(viridis)
  library(scales)
  library(MASS)        # glm.nb  (load before dplyr-heavy code; select() is masked -> use dplyr::select)
  library(mgcv)        # spatial NB-GAM
  library(spdep)       # Moran's I, spatial weights
  library(car)         # VIF
  library(ranger)      # random forest
})
# dplyr::select is masked by MASS; make the dplyr verbs win explicitly.
select <- dplyr::select
filter <- dplyr::filter

# large Socrata pages over slow filtered queries exceed R's 60s default
options(timeout = 600)

# ----------------------------------------------------------------------------
# Paths  (scripts assume the working directory is the project root, which RStudio
# sets automatically when you open nyc-womens-safety.Rproj; run_all.R enforces it)
# ----------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a)) b else a
ROOT      <- getwd()
if (!dir.exists(file.path(ROOT, "R")))
  stop("Set the working directory to the project root (open the .Rproj, or setwd() there).")
DIR_RAW   <- file.path(ROOT, "data", "raw")
DIR_PROC  <- file.path(ROOT, "data", "processed")
DIR_FIG   <- file.path(ROOT, "outputs", "figures")
DIR_TAB   <- file.path(ROOT, "outputs", "tables")
for (d in c(DIR_RAW, DIR_PROC, DIR_FIG, DIR_TAB)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

# ----------------------------------------------------------------------------
# Analysis configuration
# ----------------------------------------------------------------------------
CFG <- list(
  date_start = "2020-01-01",
  date_end   = "2022-12-31",
  # NY State Plane Long Island (ftUS) - correct projected CRS for NYC distances/areas
  crs_proj   = 2263,
  crs_geo    = 4326,
  # "Dark hours": used for the day/night identification of the lighting mechanism.
  # Defined on local clock hour of complaint start time. Sensitivity-checked in 03_models.
  night_hours = c(18:23, 0:5),
  # 5 NYC counties (state FIPS 36)
  counties = c(Bronx = "005", Kings = "047", `New York` = "061",
               Queens = "081", Richmond = "085"),
  acs_year = 2022,
  # Socrata dataset endpoints
  ds = list(
    crime      = list(domain = "data.cityofnewyork.us", id = "qgea-i56i"),
    light_311  = list(domain = "data.cityofnewyork.us", id = "erm2-nwe9"),
    pavement   = list(domain = "data.cityofnewyork.us", id = "6yyb-pb25"),
    pluto      = list(domain = "data.cityofnewyork.us", id = "64uk-42ks"),
    subway     = list(domain = "data.ny.gov",           id = "39hk-dx4f"),
    facilities = list(domain = "data.cityofnewyork.us", id = "ji82-xba5"),
    dv         = list(domain = "data.cityofnewyork.us", id = "tbf6-u8ea")
  )
)

# ----------------------------------------------------------------------------
# Socrata downloader with paging + on-disk cache
#   query: named list of SoQL params, e.g. list(`$where`=..., `$select`=...)
# ----------------------------------------------------------------------------
socrata_get <- function(domain, id, query = list(), cache = NULL,
                        page = 50000L, max_rows = Inf, refresh = FALSE) {
  if (!is.null(cache) && file.exists(cache) && !refresh) {
    message("  [cache] ", basename(cache))
    return(readr::read_csv(cache, show_col_types = FALSE, guess_max = 100000))
  }
  base <- sprintf("https://%s/resource/%s.json", domain, id)
  if (is.null(query[["$order"]])) query[["$order"]] <- ":id"  # stable, fast deep paging
  out <- list(); offset <- 0L
  repeat {
    q <- c(query, list(`$limit` = page, `$offset` = offset))
    qs <- paste(sprintf("%s=%s", names(q),
                        vapply(q, function(x) URLencode(as.character(x), reserved = TRUE), "")),
                collapse = "&")
    url <- paste0(base, "?", qs)
    chunk <- NULL
    for (attempt in 1:4) {                            # retry w/ backoff on timeouts
      chunk <- tryCatch(jsonlite::fromJSON(url), error = function(e) NULL)
      if (!is.null(chunk)) break
      Sys.sleep(2^attempt)
    }
    if (is.null(chunk)) stop("socrata_get: failed after retries at offset ", offset)
    if (length(chunk) == 0 || (is.data.frame(chunk) && nrow(chunk) == 0)) break
    out[[length(out) + 1]] <- chunk
    got <- nrow(chunk); offset <- offset + got
    message(sprintf("  [%s] fetched %s rows (total %s)", id, format(got, big.mark=","),
                    format(offset, big.mark=",")))
    if (got < page || offset >= max_rows) break
  }
  df <- dplyr::bind_rows(out)
  # Socrata returns nested point objects (e.g. georeference) as list/df columns;
  # drop them so the frame stays flat/atomic (lat & lon are kept as plain columns).
  keep <- vapply(df, function(col) is.atomic(col) && !is.matrix(col), logical(1))
  df <- df[, keep, drop = FALSE]
  if (!is.null(cache)) readr::write_csv(df, cache)
  df
}

# ----------------------------------------------------------------------------
# Census ACS 5-year via the data API. Requires CENSUS_API_KEY (free, instant
# signup at https://api.census.gov/data/key_signup.html).
#   vars: named character vector of ACS variable ids
# ----------------------------------------------------------------------------
get_acs_tracts <- function(vars, year = CFG$acs_year, state = "36",
                           counties = CFG$counties, cache = NULL, refresh = FALSE) {
  if (!is.null(cache) && file.exists(cache) && !refresh) {
    message("  [cache] ", basename(cache))
    return(readr::read_csv(cache, show_col_types = FALSE, col_types = readr::cols(GEOID = "c")))
  }
  key <- Sys.getenv("CENSUS_API_KEY")
  if (!nzchar(key)) stop("CENSUS_API_KEY not set")
  get_str <- paste(c("NAME", unname(vars)), collapse = ",")
  res <- list()
  for (cty in counties) {
    url <- sprintf("https://api.census.gov/data/%d/acs/acs5?get=%s&for=tract:*&in=state:%s%%20county:%s&key=%s",
                   year, get_str, state, cty, key)
    m <- tryCatch(jsonlite::fromJSON(url), error = function(e) { Sys.sleep(2); jsonlite::fromJSON(url) })
    hdr <- m[1, ]; body <- as.data.frame(m[-1, , drop = FALSE], stringsAsFactors = FALSE)
    names(body) <- hdr
    res[[cty]] <- body
  }
  df <- dplyr::bind_rows(res)
  # rename ACS codes -> friendly names; coerce to numeric
  for (nm in names(vars)) df[[nm]] <- suppressWarnings(as.numeric(df[[vars[nm]]]))
  df <- df %>%
    mutate(GEOID = paste0(state, county, tract)) %>%
    select(GEOID, all_of(names(vars)))
  if (!is.null(cache)) readr::write_csv(df, cache)
  df
}

# ----------------------------------------------------------------------------
# Socioeconomic controls per tract.
#   * If CENSUS_API_KEY is set -> full ACS 5-year (pop, poverty, rent, value, income, %female)
#   * Otherwise -> NYC CDBG-by-tract table (population + low/moderate-income %),
#     so the whole pipeline runs with no credentials. Source recorded as attr().
# ----------------------------------------------------------------------------
boroct_to_geoid <- function(boroct) {
  boroct <- sprintf("%07s", as.character(boroct))
  cty <- c(`1` = "061", `2` = "005", `3` = "047", `4` = "081", `5` = "085")[substr(boroct, 1, 1)]
  paste0("36", cty, substr(boroct, 2, 7))
}

get_socioecon_tracts <- function(refresh = FALSE) {
  cache <- file.path(DIR_PROC, "socioecon.csv")
  if (file.exists(cache) && !refresh)
    return(readr::read_csv(cache, show_col_types = FALSE, col_types = readr::cols(GEOID = "c")))
  if (nzchar(Sys.getenv("CENSUS_API_KEY"))) {
    vars <- c(pop = "B01003_001E", pov_num = "B17001_002E", pov_den = "B17001_001E",
              rent = "B25064_001E", hvalue = "B25077_001E", income = "B19013_001E",
              female = "B01001_026E")
    df <- get_acs_tracts(vars) %>%
      mutate(disadv_pct = 100 * pov_num / pov_den,   # true poverty rate
             female_pct = 100 * female / pop) %>%
      select(GEOID, pop, disadv_pct, rent, hvalue, income, female_pct)
    src <- "ACS5"
  } else {
    message("  [socioecon] CENSUS_API_KEY not set -> NYC CDBG fallback (pop + low/mod-income %)")
    cd <- socrata_get(CFG$ds$light_311$domain, "qmcw-ur37",
                      query = list(`$select` = "boroct,totalpop,lomod_pct"),
                      cache = file.path(DIR_RAW, "cdbg_tract.csv"), refresh = refresh)
    df <- cd %>% transmute(GEOID = boroct_to_geoid(boroct),
                           pop = as.numeric(totalpop),
                           disadv_pct = as.numeric(lomod_pct)) %>%   # low/mod-income share (SES proxy)
      filter(!is.na(GEOID), pop > 0)
    src <- "CDBG"
  }
  attr(df, "source") <- src
  readr::write_csv(df, cache)
  df
}

# ----------------------------------------------------------------------------
# Census TIGER cartographic-boundary tracts (no key), clipped to NYC counties
# ----------------------------------------------------------------------------
get_tracts_sf <- function(year = 2022, state = "36", counties = CFG$counties,
                          cache = file.path(DIR_RAW, "tracts.gpkg"), refresh = FALSE) {
  if (file.exists(cache) && !refresh) { message("  [cache] tracts.gpkg"); return(st_read(cache, quiet = TRUE)) }
  zip_url <- sprintf("https://www2.census.gov/geo/tiger/GENZ%d/shp/cb_%d_%s_tract_500k.zip",
                     year, year, state)
  tmp <- tempfile(fileext = ".zip"); download.file(zip_url, tmp, quiet = TRUE)
  ex <- file.path(tempdir(), paste0("tr", year)); unzip(tmp, exdir = ex)
  shp <- list.files(ex, pattern = "\\.shp$", full.names = TRUE)[1]
  tr <- st_read(shp, quiet = TRUE) %>%
    filter(COUNTYFP %in% counties) %>%
    transmute(GEOID, ALAND = as.numeric(ALAND)) %>%
    st_transform(CFG$crs_proj)
  st_write(tr, cache, quiet = TRUE, delete_dsn = TRUE)
  tr
}

# Build an sf of points from lon/lat columns, dropping bad coords, in projected CRS
points_sf <- function(df, lon = "longitude", lat = "latitude") {
  df <- df %>% mutate(.lon = suppressWarnings(as.numeric(.data[[lon]])),
                      .lat = suppressWarnings(as.numeric(.data[[lat]]))) %>%
    filter(!is.na(.lon), !is.na(.lat), .lon < -73, .lon > -75, .lat > 40, .lat < 41.2)
  st_as_sf(df, coords = c(".lon", ".lat"), crs = CFG$crs_geo) %>% st_transform(CFG$crs_proj)
}

theme_set(theme_minimal(base_size = 12))
PAL <- list(female = "#C2185B", male = "#1565C0", night = "#283593", day = "#FBC02D")
message("setup.R loaded OK")
