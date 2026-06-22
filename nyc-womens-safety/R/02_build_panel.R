# =============================================================================
# 02_build_panel.R  --  Assemble the tract-level analysis panel
#   * geocode crimes -> tracts, split by victim sex and day/night
#   * build per-tract infrastructure exposures (independent of crime locations)
#   * join socioeconomic controls + population (exposure offset)
# Outputs: data/processed/panel_wide.csv, panel_long.csv, tracts_geo.gpkg
# =============================================================================

# -- offense classes -----------------------------------------------------------
VIOLENT_RE <- "ASSAULT|RAPE|SEX|ROBBERY|HARRAS|HARASS|MURDER|HOMICIDE|KIDNAP|STRANGUL|MENACING"

build_panel <- function(refresh = FALSE) {
  fcw <- file.path(DIR_PROC, "panel_wide.csv")
  fcl <- file.path(DIR_PROC, "panel_long.csv")
  fcg <- file.path(DIR_PROC, "tracts_geo.gpkg")
  if (all(file.exists(fcw, fcl, fcg)) && !refresh) {
    message("  [cache] panel_*.csv"); return(invisible(TRUE))
  }

  tracts  <- get_tracts_sf()
  cent    <- st_centroid(tracts)
  area_km2 <- tibble::tibble(GEOID = tracts$GEOID, area_km2 = as.numeric(tracts$ALAND) / 1e6)
  to_m <- function(d) as.numeric(units::set_units(d, "m"))
  m800 <- 800 / 0.3048   # 800 m expressed in the CRS unit (US ft) for within-distance

  # ---- crimes -> tracts, sex & day/night ------------------------------------
  cr <- fetch_crime() %>%
    mutate(hour = suppressWarnings(as.integer(substr(cmplnt_fr_tm, 1, 2))),
           period = ifelse(hour %in% CFG$night_hours, "night", "day"),
           violent = str_detect(toupper(ofns_desc %||% ""), VIOLENT_RE)) %>%
    filter(!is.na(period))
  cr_sf <- points_sf(cr) %>% st_join(tracts["GEOID"], join = st_within) %>% filter(!is.na(GEOID))
  crd <- st_drop_geometry(cr_sf)

  agg <- function(df, suffix) {
    df %>% group_by(GEOID, vic_sex, period) %>% summarise(n = n(), .groups = "drop") %>%
      tidyr::pivot_wider(names_from = c(vic_sex, period), values_from = n,
                         names_glue = paste0("n_{vic_sex}_{period}_", suffix), values_fill = 0)
  }
  counts_all <- agg(crd, "all")
  counts_vio <- agg(filter(crd, violent), "vio")

  # ---- infrastructure exposures (per tract, crime-independent) ---------------
  count_in_tract <- function(fetch_fun, colname) {
    pts <- tryCatch(points_sf(fetch_fun()), error = function(e) NULL)
    if (is.null(pts) || nrow(pts) == 0) return(tibble::tibble(GEOID = tracts$GEOID, !!colname := 0))
    pts %>% st_join(tracts["GEOID"], join = st_within) %>% st_drop_geometry() %>%
      filter(!is.na(GEOID)) %>% count(GEOID, name = colname)
  }
  lights_ct <- count_in_tract(fetch_lights,   "n_lights")
  vacant_ct <- count_in_tract(fetch_vacant,   "n_vacant")
  facils_ct <- count_in_tract(fetch_facilities, "n_facils")

  # pavement: mean segment rating per tract (lower = worse)
  pv <- fetch_pavement() %>% st_join(tracts["GEOID"], join = st_within) %>%
    st_drop_geometry() %>% filter(!is.na(GEOID)) %>%
    group_by(GEOID) %>% summarise(pavement_rating = mean(rating_num, na.rm = TRUE), .groups = "drop")

  # subway: distance (m) from centroid to nearest station + count within 800 m
  sub <- points_sf(fetch_subway())
  nn_sub <- st_nearest_feature(cent, sub)
  dist_sub <- tibble::tibble(GEOID = cent$GEOID,
                             dist_subway_m = to_m(st_distance(cent, sub[nn_sub, ], by_element = TRUE)),
                             n_subway_800m = lengths(st_is_within_distance(cent, sub, m800)))

  # women's / DV resources: distance (m) to nearest
  dv <- points_sf(fetch_dv())
  nn_dv <- st_nearest_feature(cent, dv)
  dist_dv <- tibble::tibble(GEOID = cent$GEOID,
                            dist_dv_m = to_m(st_distance(cent, dv[nn_dv, ], by_element = TRUE)))

  # ---- socioeconomic controls + assemble ------------------------------------
  se <- get_socioecon_tracts() %>% mutate(GEOID = as.character(GEOID))

  wide <- tracts %>% st_drop_geometry() %>% select(GEOID) %>%
    left_join(area_km2, "GEOID") %>%
    left_join(counts_all, "GEOID") %>% left_join(counts_vio, "GEOID") %>%
    left_join(lights_ct, "GEOID") %>% left_join(vacant_ct, "GEOID") %>%
    left_join(facils_ct, "GEOID") %>% left_join(pv, "GEOID") %>%
    left_join(dist_sub, "GEOID") %>% left_join(dist_dv, "GEOID") %>%
    left_join(se, "GEOID")

  # zero-fill crime/feature counts; densities per km^2
  cnt_cols <- grep("^n_(F|M|lights|vacant|facils)", names(wide), value = TRUE)
  wide <- wide %>% mutate(across(all_of(cnt_cols), ~ tidyr::replace_na(., 0))) %>%
    mutate(dens_lights = n_lights / area_km2,
           dens_vacant = n_vacant / area_km2,
           dens_facils = n_facils / area_km2,
           # pooled outcomes for convenience
           n_F_all = rowSums(across(c(n_F_night_all, n_F_day_all)), na.rm = TRUE),
           n_M_all = rowSums(across(c(n_M_night_all, n_M_day_all)), na.rm = TRUE),
           n_F_vio = rowSums(across(c(n_F_night_vio, n_F_day_vio)), na.rm = TRUE),
           n_M_vio = rowSums(across(c(n_M_night_vio, n_M_day_vio)), na.rm = TRUE)) %>%
    filter(!is.na(pop), pop > 0)

  # ---- long format: tract x sex x period (for interaction models) -----------
  long <- wide %>%
    select(GEOID, area_km2, pop, disadv_pct, dist_subway_m, n_subway_800m, dist_dv_m,
           dens_lights, dens_vacant, dens_facils, pavement_rating,
           starts_with("n_F_"), starts_with("n_M_")) %>%
    tidyr::pivot_longer(c(n_F_night_vio, n_F_day_vio, n_M_night_vio, n_M_day_vio),
                        names_to = "cell", values_to = "n_violent") %>%
    mutate(sex = ifelse(str_detect(cell, "_F_"), "F", "M"),
           period = ifelse(str_detect(cell, "night"), "night", "day")) %>%
    select(-cell)

  # add centroid coords (for spatial smooth / spatial CV)
  xy <- st_coordinates(cent);
  coords <- tibble::tibble(GEOID = cent$GEOID, x = xy[, 1], y = xy[, 2])
  wide <- left_join(wide, coords, "GEOID")
  long <- left_join(long, coords, "GEOID")

  readr::write_csv(wide, fcw); readr::write_csv(long, fcl)
  st_write(left_join(tracts, wide, "GEOID"), fcg, quiet = TRUE, delete_dsn = TRUE)
  message(sprintf("  panel built: %d tracts | F violent public crimes = %s | M = %s",
                  nrow(wide), format(sum(wide$n_F_vio), big.mark=","), format(sum(wide$n_M_vio), big.mark=",")))
  invisible(TRUE)
}
