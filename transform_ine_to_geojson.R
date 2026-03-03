# Transform INE data to GeoJSON format
# This script reads the combined INE JSON file with data from TWO trimesters
# and merges them to enable price comparison visualization

library(jsonlite)

# File paths
base_geojson_path <- "geojson_compras.json"
ine_data_path <- "dados_ine_combined.json"
output_path <- "geojson_compras_updated.json"

# Municipalities that should always use concelho-level data (not freguesia-level)
# These are municipalities around Porto where we want aggregate data only
aggregate_municipios <- c(
  "11A0104", # Arouca
  "11A0113", # Oliveira de Azeméis
  "11A0109", # Santa Maria da Feira
  "11A0107", # Espinho
  "11A1316", # Vila do Conde
  "11A0119" # Vale de Cambra
)

# Read the base GeoJSON (existing geojson_compras)
cat("Loading base GeoJSON...\n")
base_geojson <- fromJSON(base_geojson_path, simplifyVector = FALSE)

# Read the combined INE data
cat("Loading combined INE data...\n")
ine_data_combined <- fromJSON(ine_data_path, simplifyVector = FALSE)

# The combined file has structure: { "S5A20252": [...], "S5A20251": [...] }
# Get the indicator codes (they're sorted, so first is most recent)
indicator_codes <- names(ine_data_combined)
cat(sprintf(
  "\nFound %d indicators in combined file:\n",
  length(indicator_codes)
))
for (code in indicator_codes) {
  cat(sprintf("  %s\n", code))
}

# Assuming indicators are sorted with most recent first
# S5A20252 = 2nd trimester 2025, S5A20251 = 1st trimester 2025
indicator_current <- indicator_codes[1]
indicator_previous <- indicator_codes[2]

# Extract the actual data from each indicator
ine_data_current <- ine_data_combined[[indicator_current]][[1]]
ine_data_previous <- ine_data_combined[[indicator_previous]][[1]]

# Get the time period names
period_current <- names(ine_data_current$Dados)[1]
period_previous <- names(ine_data_previous$Dados)[1]

cat(sprintf("\nComparing:\n"))
cat(sprintf(
  "  Current period:  %s (from %s)\n",
  period_current,
  indicator_current
))
cat(sprintf(
  "  Previous period: %s (from %s)\n",
  period_previous,
  indicator_previous
))

# Function to create lookup table for a given period
# Returns ALL entries (value + geocode) for each municipality name
# This handles duplicate names across different regions
create_lookup <- function(period_data) {
  lookup <- list()
  for (record in period_data) {
    municipality_name <- toupper(record$geodsg) # Normalize to uppercase for matching
    value <- as.numeric(record$valor)
    geocode <- record$geocod

    # Store ALL occurrences - create list if doesn't exist
    if (is.null(lookup[[municipality_name]])) {
      lookup[[municipality_name]] <- list()
    }

    # Append this entry to the list
    lookup[[municipality_name]][[
      length(lookup[[municipality_name]]) + 1
    ]] <- list(
      value = value,
      geocode = geocode
    )
  }
  return(lookup)
}

# Create lookup tables for both periods
cat("\nCreating lookup tables...\n")
lookup_current <- create_lookup(ine_data_current$Dados[[period_current]])
lookup_previous <- create_lookup(ine_data_previous$Dados[[period_previous]])

cat(sprintf("  Current period:  %d municipalities\n", length(lookup_current)))
cat(sprintf("  Previous period: %d municipalities\n", length(lookup_previous)))

# Helper function to determine region from geocode
get_region_from_geocode <- function(geocode) {
  if (is.null(geocode) || is.na(geocode)) {
    return("unknown")
  }
  if (grepl("^3", geocode)) {
    return("madeira")
  }
  if (grepl("^2", geocode)) {
    return("acores")
  }
  return("continental")
}

# Helper function to get coordinates from feature for region detection
get_region_from_coords <- function(feature) {
  if (is.null(feature$geometry) || is.null(feature$geometry$coordinates)) {
    return("continental")
  }

  # Navigate to the first coordinate point
  coords <- feature$geometry$coordinates
  while (
    is.list(coords[[1]]) && length(coords[[1]]) > 0 && is.list(coords[[1]][[1]])
  ) {
    coords <- coords[[1]]
  }
  if (is.list(coords[[1]])) {
    coords <- coords[[1]]
  }

  lon <- coords[[1]]

  # Madeira is around longitude -17 to -16
  if (lon < -15) {
    return("madeira")
  }
  # Açores is around longitude -31 to -25
  if (lon < -24) {
    return("acores")
  }
  # Continental Portugal is around -9 to -6
  return("continental")
}

# Helper function to get município code from geocode
get_municipio_code <- function(geocode) {
  if (is.null(geocode) || nchar(geocode) < 7) {
    return(NULL)
  }
  # Municipality codes are the first 7 characters
  return(substr(geocode, 1, 7))
}

# Helper function to find município-level data by geocode prefix
find_municipio_data <- function(lookup_table, municipio_code, region) {
  if (is.null(municipio_code)) {
    return(NULL)
  }

  # Search through all entries in the lookup table
  for (name in names(lookup_table)) {
    entries <- lookup_table[[name]]
    for (entry in entries) {
      # Check if this entry's geocode matches the município code
      if (!is.null(entry$geocode) && entry$geocode == municipio_code) {
        entry_region <- get_region_from_geocode(entry$geocode)
        if (entry_region == region) {
          return(entry)
        }
      }
    }
  }
  return(NULL)
}

# Update the GeoJSON features with values from both periods
cat("\nMatching and updating GeoJSON features...\n")

matched_both <- 0
matched_current_only <- 0
matched_previous_only <- 0
matched_none <- 0

for (i in seq_along(base_geojson$features)) {
  feature <- base_geojson$features[[i]]
  municipality_name <- feature$properties$lugar
  municipality_name_normalized <- toupper(municipality_name)

  # Special handling: If this is a união within a consolidated município, use the município name
  if (grepl("OLIVEIRA DE AZEMÉIS.*SANTIAGO", municipality_name_normalized, ignore.case = TRUE)) {
    municipality_name_normalized <- "OLIVEIRA DE AZEMÉIS"
  }

  # Determine the region of this feature from its coordinates
  feature_region <- get_region_from_coords(feature)

  current_lookup_entries <- lookup_current[[municipality_name_normalized]]
  previous_lookup_entries <- lookup_previous[[municipality_name_normalized]]

  # Extract values and geocodes, matching by region if there are duplicates
  current_value <- NULL
  current_geocode <- NULL
  if (!is.null(current_lookup_entries)) {
    # Search through all entries for this name to find the matching region
    for (entry in current_lookup_entries) {
      lookup_region <- get_region_from_geocode(entry$geocode)
      if (lookup_region == feature_region) {
        current_value <- entry$value
        current_geocode <- entry$geocode
        break # Found the right one
      }
    }
  }

  # Check if this feature should use município-level data
  if (!is.null(current_geocode)) {
    municipio_code <- get_municipio_code(current_geocode)
    if (!is.null(municipio_code) && municipio_code %in% aggregate_municipios) {
      # This feature belongs to a município that should use aggregate data
      municipio_entry <- find_municipio_data(
        lookup_current,
        municipio_code,
        feature_region
      )
      if (!is.null(municipio_entry)) {
        current_value <- municipio_entry$value
        current_geocode <- municipio_entry$geocode
      }
    }
  }

  previous_value <- NULL
  if (!is.null(previous_lookup_entries)) {
    # Search through all entries for this name to find the matching region
    for (entry in previous_lookup_entries) {
      lookup_region <- get_region_from_geocode(entry$geocode)
      if (lookup_region == feature_region) {
        previous_value <- entry$value
        break # Found the right one
      }
    }
  }

  # Check if this feature should use município-level data for previous period
  if (!is.null(current_geocode)) {
    municipio_code <- get_municipio_code(current_geocode)
    if (!is.null(municipio_code) && municipio_code %in% aggregate_municipios) {
      municipio_entry <- find_municipio_data(
        lookup_previous,
        municipio_code,
        feature_region
      )
      if (!is.null(municipio_entry)) {
        previous_value <- municipio_entry$value
      }
    }
  }

  # Store both values (will be NULL if not found or wrong region)
  base_geojson$features[[i]]$properties$RENDA_current <- current_value
  base_geojson$features[[i]]$properties$RENDA_previous <- previous_value
  base_geojson$features[[i]]$properties$period_current <- period_current
  base_geojson$features[[i]]$properties$period_previous <- period_previous
  base_geojson$features[[i]]$properties$geocode <- current_geocode # Add geocode for accurate region detection
  base_geojson$features[[i]]$properties$region <- feature_region # Add region for debugging

  # Remove old RENDA field if it exists
  base_geojson$features[[i]]$properties$RENDA <- NULL

  # Count matches
  has_current <- !is.null(current_value)
  has_previous <- !is.null(previous_value)

  if (has_current && has_previous) {
    matched_both <- matched_both + 1
  } else if (has_current) {
    matched_current_only <- matched_current_only + 1
  } else if (has_previous) {
    matched_previous_only <- matched_previous_only + 1
  } else {
    matched_none <- matched_none + 1
  }
}

# Print statistics
cat(sprintf("\nMatching statistics:\n"))
cat(sprintf("  Both periods:     %d municipalities\n", matched_both))
cat(sprintf("  Current only:     %d municipalities\n", matched_current_only))
cat(sprintf("  Previous only:    %d municipalities\n", matched_previous_only))
cat(sprintf("  No data:          %d municipalities\n", matched_none))
cat(sprintf("  Total features:   %d\n", length(base_geojson$features)))

# Save the result
cat(sprintf("\nSaving result to %s...\n", output_path))
write_json(base_geojson, output_path, auto_unbox = TRUE, pretty = FALSE)

cat("\nDone! GeoJSON file updated successfully.\n")
cat(sprintf("\nMetadata:\n"))
cat(sprintf("  Indicator: %s\n", ine_data_current$IndicadorDsg))
cat(sprintf("  Last update: %s\n", ine_data_current$DataUltimoAtualizacao))
cat(sprintf("  Comparing: %s vs %s\n", period_current, period_previous))
