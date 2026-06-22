# =============================================================================
# run_all.R  --  Reproduce the full analysis end to end.
#   Rscript R/run_all.R         (from the project root)
# Optional: set CENSUS_API_KEY for full ACS controls; otherwise a no-key
# NYC fallback (population + low/mod-income %) is used automatically.
# =============================================================================
stopifnot("Run from the project root (open nyc-womens-safety.Rproj)" = dir.exists("R"))

source("R/00_setup.R")
source("R/01_fetch_data.R")
source("R/02_build_panel.R")
source("R/03_models.R")
source("R/04_figures.R")

message("\n[1/3] Building tract panel ...")
build_panel()                 # downloads + caches on first run

message("\n[2/3] Fitting models ...")
res <- run_models()

message("\n[3/3] Rendering figures ...")
make_figures()

message("\nDone. See outputs/tables/ and outputs/figures/.")
