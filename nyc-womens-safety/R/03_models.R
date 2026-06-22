# =============================================================================
# 03_models.R  --  Spatial diagnostics + count models + gendered/temporal design
#   (1) Moran's I  (2) OLS vs NB vs spatial NB-GAM  (3) gender & day/night
#   (4) VIF  (5) spatial block cross-validation  (6) Random Forest comparison
# Outputs: outputs/tables/*.csv, outputs/models.rds
# =============================================================================

# transform helpers: log1p heavy-tailed predictors, then z-score for comparable IRRs
.z   <- function(x) as.numeric(scale(x))
.zl  <- function(x) as.numeric(scale(log1p(x)))

PREDICTORS <- c("dens_lights", "dens_vacant", "pavement_rating", "dist_subway_m",
                "n_subway_800m", "dist_dv_m", "dens_facils", "disadv_pct")

prep_model_data <- function(wide) {
  wide %>%
    mutate(
      z_lights   = .zl(dens_lights),
      z_vacant   = .zl(dens_vacant),
      z_pavement = .z(ifelse(is.na(pavement_rating), median(pavement_rating, na.rm = TRUE), pavement_rating)),
      z_subway_d = .zl(dist_subway_m),
      z_subway_n = .zl(n_subway_800m),
      z_dv_d     = .zl(dist_dv_m),
      z_facils   = .zl(dens_facils),
      z_disadv   = .z(disadv_pct),
      log_pop    = log(pop),
      log_area   = log(area_km2)) %>%
    filter(is.finite(log_pop))
}
ZVARS <- c("z_lights","z_vacant","z_pavement","z_subway_d","z_subway_n","z_dv_d","z_facils","z_disadv")

run_models <- function() {
  gc_chr <- readr::cols(GEOID = "c")
  wide <- readr::read_csv(file.path(DIR_PROC, "panel_wide.csv"), show_col_types = FALSE, col_types = gc_chr)
  long <- readr::read_csv(file.path(DIR_PROC, "panel_long.csv"), show_col_types = FALSE, col_types = gc_chr)
  tr   <- st_read(file.path(DIR_PROC, "tracts_geo.gpkg"), quiet = TRUE)
  md   <- prep_model_data(wide)
  rhs  <- paste(ZVARS, collapse = " + ")

  out <- list()

  ## (1) Spatial autocorrelation -------------------------------------------------
  trm <- tr %>% filter(GEOID %in% md$GEOID)
  trm <- trm[match(md$GEOID, trm$GEOID), ]
  nb  <- spdep::poly2nb(trm, queen = TRUE)
  lw  <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
  rate_F <- md$n_F_vio / md$pop
  moran_raw <- spdep::moran.test(rate_F, lw, zero.policy = TRUE)

  ## (2) Models for FEMALE violent public crime ---------------------------------
  f_nb  <- as.formula(paste("n_F_vio ~", rhs, "+ offset(log_pop)"))
  m_ols <- lm(as.formula(paste("I(n_F_vio/pop*1000) ~", rhs)), data = md)        # flawed baseline
  m_nb  <- MASS::glm.nb(f_nb, data = md)
  m_gam <- mgcv::gam(as.formula(paste("n_F_vio ~", rhs, "+ s(x, y, k = 60) + offset(log_pop)")),
                     family = mgcv::nb(), data = md, method = "REML")

  # Moran's I on residuals: does the spatial term absorb autocorrelation?
  moran_nb  <- spdep::moran.test(residuals(m_nb,  type = "pearson"), lw, zero.policy = TRUE)
  moran_gam <- spdep::moran.test(residuals(m_gam, type = "pearson"), lw, zero.policy = TRUE)
  out$moran <- tibble::tibble(
    model = c("raw rate", "NB residuals", "spatial NB-GAM residuals"),
    morans_I = c(moran_raw$estimate[1], moran_nb$estimate[1], moran_gam$estimate[1]),
    p_value  = c(moran_raw$p.value, moran_nb$p.value, moran_gam$p.value))

  ## (3) VIF (multicollinearity) ------------------------------------------------
  out$vif <- tibble::enframe(car::vif(m_nb), name = "predictor", value = "VIF")

  ## (4) Coefficient table (incidence-rate ratios) ------------------------------
  irr <- function(m, label) {
    s <- summary(m)$coefficients
    tibble::tibble(model = label, term = rownames(s),
                   IRR = exp(s[, 1]), lo = exp(s[, 1] - 1.96 * s[, 2]),
                   hi = exp(s[, 1] + 1.96 * s[, 2]), p = s[, 4]) %>%
      filter(term %in% ZVARS)
  }
  m_nb_M <- MASS::glm.nb(as.formula(paste("n_M_vio ~", rhs, "+ offset(log_pop)")), data = md)
  out$coef_nb <- dplyr::bind_rows(irr(m_nb, "Female"), irr(m_nb_M, "Male"))

  ## (5) Gendered + day/night design (pooled long model) ------------------------
  ld <- long %>% mutate(
      z_lights = .zl(dens_lights), z_vacant = .zl(dens_vacant),
      z_pavement = .z(ifelse(is.na(pavement_rating), median(pavement_rating, na.rm=TRUE), pavement_rating)),
      z_subway_d = .zl(dist_subway_m), z_dv_d = .zl(dist_dv_m), z_disadv = .z(disadv_pct),
      sex = factor(sex, c("M","F")), period = factor(period, c("day","night")),
      log_pop = log(pop)) %>% filter(is.finite(log_pop))
  infra <- c("z_lights","z_vacant","z_pavement","z_subway_d","z_dv_d")
  # sex interaction: are infrastructure effects stronger for women?
  m_sex <- MASS::glm.nb(as.formula(paste0("n_violent ~ (", paste(infra, collapse="+"),
                        ") * sex + z_disadv + period + offset(log_pop)")), data = ld)
  # lighting x night (mechanism test), female-stratified
  m_night <- MASS::glm.nb(as.formula(paste0("n_violent ~ z_lights * period * sex + z_vacant + ",
                        "z_pavement + z_subway_d + z_dv_d + z_disadv + offset(log_pop)")), data = ld)
  tidy_terms <- function(m, label, keep) {
    s <- summary(m)$coefficients
    tibble::tibble(model = label, term = rownames(s), IRR = exp(s[,1]),
                   lo = exp(s[,1]-1.96*s[,2]), hi = exp(s[,1]+1.96*s[,2]), p = s[,4]) %>%
      filter(grepl(keep, term))
  }
  out$coef_sex   <- tidy_terms(m_sex, "sex-interaction", ":sexF|^z_")
  out$coef_night <- tidy_terms(m_night, "lighting x night x sex", "z_lights")

  ## (6) Spatial block cross-validation: NB vs spatial-GAM vs RF -----------------
  set.seed(42)
  nbk <- 6
  md$blk <- interaction(cut(md$x, nbk, labels = FALSE), cut(md$y, nbk, labels = FALSE))
  blks <- unique(md$blk); folds <- split(blks, sample(rep(1:5, length.out = length(blks))))
  rmse <- function(a, b) sqrt(mean((a - b)^2))
  res <- lapply(folds, function(testblk) {
    tr_i <- md[!md$blk %in% testblk, ]; te_i <- md[md$blk %in% testblk, ]
    nb_i  <- tryCatch(MASS::glm.nb(f_nb, data = tr_i), error = function(e) NULL)
    gam_i <- mgcv::gam(as.formula(paste("n_F_vio ~", rhs, "+ s(x,y,k=40) + offset(log_pop)")),
                       family = mgcv::nb(), data = tr_i, method = "REML")
    rf_i  <- ranger::ranger(as.formula(paste("I(n_F_vio/pop) ~", paste(c(ZVARS,"x","y"), collapse="+"))),
                            data = tr_i, num.trees = 300)
    obs <- te_i$n_F_vio
    c(NB  = if (is.null(nb_i)) NA else rmse(obs, predict(nb_i, te_i, type = "response")),
      GAM = rmse(obs, as.numeric(predict(gam_i, te_i, type = "response"))),
      RF  = rmse(obs, predict(rf_i, te_i)$predictions * te_i$pop))
  })
  out$cv <- tibble::as_tibble(do.call(rbind, res)) %>%
    summarise(across(everything(), ~ mean(., na.rm = TRUE))) %>%
    tidyr::pivot_longer(everything(), names_to = "model", values_to = "spatial_CV_RMSE")

  ## RF importance (full fit) ---------------------------------------------------
  rf_full <- ranger::ranger(as.formula(paste("I(n_F_vio/pop) ~", paste(c(ZVARS,"x","y"), collapse="+"))),
                            data = md, num.trees = 800, importance = "permutation")
  out$rf_importance <- tibble::enframe(ranger::importance(rf_full), "predictor", "importance") %>%
    arrange(desc(importance))

  ## save -----------------------------------------------------------------------
  for (nm in c("moran","vif","coef_nb","coef_sex","coef_night","cv","rf_importance"))
    readr::write_csv(out[[nm]], file.path(DIR_TAB, paste0(nm, ".csv")))
  saveRDS(list(m_ols=m_ols, m_nb=m_nb, m_nb_M=m_nb_M, m_gam=m_gam, m_sex=m_sex, m_night=m_night,
               rf_full=rf_full, lw=lw, out=out), file.path(DIR_PROC, "models.rds"))
  message("  models complete; tables written to outputs/tables/")
  out
}
