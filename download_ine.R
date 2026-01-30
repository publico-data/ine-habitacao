library(httr)
library(jsonlite)

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================

INDICADOR <- "0012234"
START_YEAR <- 2021
START_QUARTER <- 1

# =============================================================================
# AUTO-DETECT PERIODS
# =============================================================================

# Get current date and calculate current quarter
current_date <- Sys.Date()
current_year <- as.integer(format(current_date, "%Y"))
current_month <- as.integer(format(current_date, "%m"))
current_quarter <- ceiling(current_month / 3)

# INE typically releases data 2-3 months after quarter ends
# So we try to fetch up to the previous quarter
if (current_quarter == 1) {
  latest_year <- current_year - 1
  latest_quarter <- 4
} else {
  latest_year <- current_year
  latest_quarter <- current_quarter - 1
}

# Generate all period codes from START to latest
PERIODO <- c()
for (year in START_YEAR:latest_year) {
  end_q <- if (year == latest_year) latest_quarter else 4
  start_q <- if (year == START_YEAR) START_QUARTER else 1
  for (q in start_q:end_q) {
    PERIODO <- c(PERIODO, paste0("S5A", year, q))
  }
}

# Reverse to have newest first
PERIODO <- rev(PERIODO)

cat("=============================================================================\n")
cat("INE Housing Data Extraction\n")
cat("=============================================================================\n\n")
cat("Date:", format(current_date, "%Y-%m-%d"), "\n")
cat("Periods to download:", length(PERIODO), "\n")
cat("Range:", tail(PERIODO, 1), "to", head(PERIODO, 1), "\n\n")

# =============================================================================
# DOWNLOAD
# =============================================================================

todos_dados <- list()

for (periodo in PERIODO) {
  url <- paste0(
    "https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2",
    "&varcd=", INDICADOR,
    "&Dim1=", periodo,
    "&Dim3=H1",
    "&lang=PT"
  )

  cat("Downloading:", periodo, "... ")

  tryCatch({
    response <- GET(url, timeout(30))

    if (status_code(response) == 200) {
      dados <- content(response, as = "parsed", encoding = "UTF-8")

      if (length(dados) > 0 && !is.null(dados[[1]]$Dados)) {
        todos_dados[[periodo]] <- dados
        cat("OK -", length(dados[[1]]$Dados[[1]]), "records\n")
      } else {
        cat("No data available yet\n")
      }
    } else {
      cat("Error:", status_code(response), "\n")
    }
  }, error = function(e) {
    cat("Error:", e$message, "\n")
  })
}

# =============================================================================
# SAVE RESULTS
# =============================================================================

if (length(todos_dados) > 0) {
  cat("\n=============================================================================\n")
  cat("Saving files\n")
  cat("=============================================================================\n\n")

  # Save individual period files
  for (periodo in names(todos_dados)) {
    output_file <- paste0("dados_ine_", periodo, ".json")
    write_json(todos_dados[[periodo]], output_file, pretty = TRUE, auto_unbox = TRUE)
    cat("Saved:", output_file, "\n")
  }

  # Save combined file
  output_combined <- paste0("dados_ine_combined_", format(Sys.Date(), "%Y%m%d"), ".json")
  write_json(todos_dados, output_combined, pretty = TRUE, auto_unbox = TRUE)
  cat("\nCombined file:", output_combined, "\n")

  cat("\nTotal periods:", length(todos_dados), "\n")
  cat("Latest period:", names(todos_dados)[1], "\n")
} else {
  cat("\nNo data was downloaded\n")
  quit(status = 1)
}
