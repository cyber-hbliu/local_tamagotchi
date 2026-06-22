# =============================================================================
# 04_figures.R  --  Publication figures (saved to outputs/figures/*.png)
# Run after 02_build_panel.R and 03_models.R.
# =============================================================================

make_figures <- function() {
  wide <- readr::read_csv(file.path(DIR_PROC, "panel_wide.csv"), show_col_types = FALSE,
                          col_types = readr::cols(GEOID = "c"))
  geo  <- st_read(file.path(DIR_PROC, "tracts_geo.gpkg"), quiet = TRUE)
  M    <- readRDS(file.path(DIR_PROC, "models.rds"))
  sv   <- function(name, p, w = 7, h = 5) ggsave(file.path(DIR_FIG, name), p, width = w, height = h, dpi = 300, bg = "white")
  map_theme <- theme_void(base_size = 11) + theme(legend.position = "right")

  ## 1. Temporal: female violent public crime by hour ---------------------------
  cr <- fetch_crime() %>%
    mutate(hour = suppressWarnings(as.integer(substr(cmplnt_fr_tm, 1, 2))),
           violent = str_detect(toupper(ofns_desc %||% ""),
                      "ASSAULT|RAPE|SEX|ROBBERY|HARRAS|HARASS|MURDER|HOMICIDE|KIDNAP|STRANGUL|MENACING")) %>%
    filter(vic_sex == "F", violent, !is.na(hour))
  hourly <- cr %>% count(hour) %>% mutate(night = hour %in% CFG$night_hours)
  p1 <- ggplot(hourly, aes(hour, n, fill = night)) +
    geom_col() +
    scale_fill_manual(values = c(`TRUE` = PAL$night, `FALSE` = PAL$day),
                      labels = c("Day (06–17h)", "Night (18–05h)"), name = NULL) +
    labs(title = "Female violent public-space victimization by hour of day",
         subtitle = "NYC, 2020–2022", x = "Hour", y = "Incidents") +
    scale_x_continuous(breaks = seq(0, 23, 3))
  sv("fig1_temporal.png", p1)

  ## 2. Map: female violent crime rate (per 1,000 residents) --------------------
  geo <- geo %>% mutate(rate_F = 1000 * n_F_vio / pop,
                        rate_F = ifelse(is.finite(rate_F), pmin(rate_F, quantile(rate_F, .98, na.rm = TRUE)), NA))
  p2 <- ggplot(geo) + geom_sf(aes(fill = rate_F), color = NA) +
    scale_fill_viridis(option = "magma", direction = -1, name = "per 1,000\nresidents", na.value = "grey90") +
    labs(title = "Female violent public-space crime rate by census tract") + map_theme
  sv("fig2_map_crime.png", p2, w = 7, h = 6)

  ## 3. Map: broken-streetlight complaint density ------------------------------
  p3 <- ggplot(geo) + geom_sf(aes(fill = pmin(dens_lights, quantile(dens_lights, .98, na.rm = TRUE))),
                              color = NA) +
    scale_fill_viridis(option = "viridis", name = "311 reports\nper km²", na.value = "grey90") +
    labs(title = "Broken-streetlight (311) complaint density by census tract") + map_theme
  sv("fig3_map_lights.png", p3, w = 7, h = 6)

  ## 4. Forest plot: Female vs Male incidence-rate ratios -----------------------
  lab <- c(z_lights = "Broken-light density", z_vacant = "Vacant-land density",
           z_pavement = "Pavement quality", z_subway_d = "Distance to subway",
           z_subway_n = "Subway stations ≤0.8km", z_dv_d = "Distance to women's resource",
           z_facils = "Facility density", z_disadv = "Socioecon. disadvantage")
  cf <- M$out$coef_nb %>% mutate(label = lab[term])
  p4 <- ggplot(cf, aes(IRR, label, color = model)) +
    geom_vline(xintercept = 1, linetype = 2, color = "grey50") +
    geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = .5)) +
    scale_color_manual(values = c(Female = PAL$female, Male = PAL$male), name = "Victim sex") +
    labs(title = "Infrastructure & public violence: incidence-rate ratios",
         subtitle = "Negative-binomial models · per +1 SD · log-population offset",
         x = "Incidence-rate ratio (log scale)", y = NULL) +
    scale_x_log10()
  sv("fig4_forest.png", p4, w = 8, h = 5)

  ## 5. Moran scatterplot (spatial autocorrelation of female crime rate) --------
  png(file.path(DIR_FIG, "fig5_moran.png"), width = 1800, height = 1500, res = 300)
  md <- prep_model_data(wide)
  spdep::moran.plot(md$n_F_vio / md$pop, M$lw, zero.policy = TRUE,
                    xlab = "Female violent crime rate", ylab = "Spatially lagged rate",
                    main = "Moran scatterplot (I = 0.11, p < 0.001)")
  dev.off()

  ## 6. Day vs night effect of broken lighting ---------------------------------
  b <- coef(M$m_night); V <- vcov(M$m_night)
  i1 <- "z_lights"; i2 <- "z_lights:periodnight"
  day_b <- b[i1]; night_b <- b[i1] + b[i2]
  day_se <- sqrt(V[i1, i1]); night_se <- sqrt(V[i1, i1] + V[i2, i2] + 2 * V[i1, i2])
  eff <- tibble::tibble(period = c("Day", "Night"),
                        IRR = exp(c(day_b, night_b)),
                        lo = exp(c(day_b - 1.96 * day_se, night_b - 1.96 * night_se)),
                        hi = exp(c(day_b + 1.96 * day_se, night_b + 1.96 * night_se)))
  p6 <- ggplot(eff, aes(period, IRR, color = period)) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey50") +
    geom_pointrange(aes(ymin = lo, ymax = hi), size = .9) +
    scale_color_manual(values = c(Day = PAL$day, Night = PAL$night), guide = "none") +
    labs(title = "Effect of broken-streetlight density, day vs. night",
         subtitle = "IRR per +1 SD; the lighting mechanism should bind after dark",
         x = NULL, y = "Incidence-rate ratio")
  sv("fig6_day_night.png", p6, w = 5, h = 5)

  ## 7. Spatial CV & RF importance ---------------------------------------------
  p7 <- ggplot(M$out$cv, aes(reorder(model, spatial_CV_RMSE), spatial_CV_RMSE, fill = model)) +
    geom_col(show.legend = FALSE) + coord_flip() +
    labs(title = "Spatial block cross-validation (lower = better)", x = NULL, y = "RMSE")
  sv("fig7_spatial_cv.png", p7, w = 6, h = 3.5)

  imp <- M$out$rf_importance %>% mutate(label = ifelse(predictor %in% names(lab), lab[predictor], predictor))
  p8 <- ggplot(imp, aes(reorder(label, importance), importance)) +
    geom_col(fill = PAL$female) + coord_flip() +
    labs(title = "Random-forest permutation importance (female crime)", x = NULL, y = "Importance")
  sv("fig8_rf_importance.png", p8, w = 6.5, h = 4)

  message("  figures written to outputs/figures/ (", length(list.files(DIR_FIG, "png$")), " files)")
}
