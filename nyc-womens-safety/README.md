# Infrastructure & Women's Public Safety in New York City

A spatial, gendered re-analysis of public-space violence against women in NYC
(2020–2022), linking police-complaint data to the *physical condition* of urban
infrastructure — broken streetlights, pavement quality, vacant land, and transit
access — at the census-tract scale.

This is a methodological rebuild of an earlier capstone. It keeps the research
question and the public-space framing but replaces the empirical strategy with
one that supports the claims being made.

## What changed vs. the original

| Weakness in the original | Fix here |
|---|---|
| Linear regression of crime **counts** | Negative-binomial model with population offset |
| **Spatial autocorrelation** ignored | Moran's *I* diagnostics + spatial NB-GAM `s(x,y)`; spatial block CV |
| No exposure / denominator | `log(population)` offset (+ ambient-population caveat) |
| "Women's safety" asserted, never tested | Joint female/male models + `infrastructure × sex` interactions |
| Lighting assumed, never tested at night | `broken-light × night × sex` mechanism test |
| Distance measured *from crimes* (circular) | Exposures measured per tract, independent of crime |
| No validation, no multicollinearity check | Spatial cross-validation, VIF, model comparison (NB / GAM / RF) |

## Key findings

- Female crime rates are strongly spatially clustered (Moran's *I* ≈ 0.11); an
  aspatial model barely dents it, the spatial term more than halves it.
- Pavement quality, transit access, facility density, and broken-light density
  are all robustly associated with public violence — for **both** sexes.
- A subset of effects (transit proximity, pavement) differ **significantly by
  sex**: women's victimisation is not just a rescaling of men's.
- The broken-light association is **directionally stronger at night**, as theory
  predicts, but the female-specific nighttime amplification is not statistically
  robust — reported as a qualified finding, not a headline.

## Reproduce

```bash
# from this folder (or open nyc-womens-safety.Rproj in RStudio / VS Code)
Rscript R/run_all.R
```

All datasets are public and downloaded at run time (cached under `data/`).
Outputs land in `outputs/figures/` and `outputs/tables/`; render the writeup
with `quarto render report/report.qmd`.

**Census controls (optional):** set a free
[Census API key](https://api.census.gov/data/key_signup.html) for full ACS
controls:

```r
Sys.setenv(CENSUS_API_KEY = "your_key")
```

Without a key the pipeline automatically falls back to a NYC tract table
(population + low/moderate-income share), so it runs with **no credentials**.

## Project layout

```
R/
  00_setup.R         packages, config, data-access helpers (Socrata, Census, TIGER)
  01_fetch_data.R    download + cache every raw layer
  02_build_panel.R   geocode crimes -> tracts; build per-tract exposures + controls
  03_models.R        Moran's I, NB / spatial-GAM / RF, gender & day-night, VIF, CV
  04_figures.R       publication figures
  run_all.R          end-to-end
report/report.qmd    the writeup (HTML / PDF)
outputs/             figures + tables
```

## Data sources

NYPD Complaint Data (`qgea-i56i`) · 311 Service Requests (`erm2-nwe9`) · DOT
Street Pavement Ratings (`6yyb-pb25`) · PLUTO (`64uk-42ks`) · MTA Subway Stations
(`39hk-dx4f`) · NYC Facilities Database (`ji82-xba5`) · Census ACS / TIGER · NYC
CDBG tract table (`qmcw-ur37`).

## Requirements

R ≥ 4.1 with `sf, spdep, mgcv, MASS, ranger, car, dplyr, tidyr, readr, stringr,
lubridate, jsonlite, ggplot2, viridis, scales` (plus `quarto` to render the
report). System libraries: GDAL, GEOS, PROJ, udunits.
