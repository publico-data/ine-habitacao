library(httr)
library(jsonlite)

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================

INDICADOR <- "0012234"
NUM_QUARTERS <- 18  # Rolling window: always keep this many quarters

# =============================================================================
# AUTO-DETECT PERIODS (Rolling Window)
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

# Generate period codes going back NUM_QUARTERS from latest
PERIODO <- c()
year <- latest_year
quarter <- latest_quarter

for (i in 1:NUM_QUARTERS) {
  PERIODO <- c(PERIODO, paste0("S5A", year, quarter))

  # Move to previous quarter
  quarter <- quarter - 1
  if (quarter == 0) {
    quarter <- 4
    year <- year - 1
  }
}

# PERIODO is already newest first

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

  # Save combined file (fixed name for consistency)
  output_combined <- "dados_ine_combined.json"
  write_json(todos_dados, output_combined, pretty = TRUE, auto_unbox = TRUE)
  cat("\nCombined file:", output_combined, "\n")

  # =============================================================================
  # CLEANUP: Remove old quarter files outside the rolling window
  # =============================================================================

  cat("\n=============================================================================\n")
  cat("Cleanup\n")
  cat("=============================================================================\n\n")

  # Find all existing period files
  existing_files <- list.files(pattern = "^dados_ine_S5A[0-9]{5}\\.json$")
  current_periods <- names(todos_dados)

  for (file in existing_files) {
    # Extract period code from filename
    periodo <- sub("dados_ine_", "", sub("\\.json$", "", file))

    if (!(periodo %in% current_periods)) {
      cat("Removing old file:", file, "\n")
      file.remove(file)
    }
  }

  # Also remove old dated combined files
  old_combined <- list.files(pattern = "^dados_ine_combined_[0-9]{8}\\.json$")
  for (file in old_combined) {
    cat("Removing old combined file:", file, "\n")
    file.remove(file)
  }

  cat("\nTotal periods:", length(todos_dados), "\n")
  cat("Latest period:", names(todos_dados)[1], "\n")
  cat("Oldest period:", names(todos_dados)[length(todos_dados)], "\n")
} else {
  cat("\nNo data was downloaded\n")
  quit(status = 1)
}
