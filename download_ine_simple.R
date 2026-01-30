library(httr)
library(jsonlite)

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================

# Código do indicador
INDICADOR <- "0012234"

# Períodos: S5A + ano + trimestre (1-4)
# De 2021 Q1 até 2025 Q2
PERIODO <- c(
  # 2025
  "S5A20252", "S5A20251",
  # 2024
  "S5A20244", "S5A20243", "S5A20242", "S5A20241",
  # 2023
  "S5A20234", "S5A20233", "S5A20232", "S5A20231",
  # 2022
  "S5A20224", "S5A20223", "S5A20222", "S5A20221",
  # 2021
  "S5A20214", "S5A20213", "S5A20212", "S5A20211"
)

# =============================================================================
# DOWNLOAD
# =============================================================================

cat("Fazendo download da API do INE...\n")
cat("Períodos a descarregar:", paste(PERIODO, collapse = ", "), "\n\n")

# Lista para guardar todos os dados
todos_dados <- list()

# Loop por cada período
for (periodo in PERIODO) {
  # URL da API
  url <- paste0(
    "https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2",
    "&varcd=",
    INDICADOR,
    "&Dim1=",
    periodo,

    "&Dim3=H1", # Categoria: Total
    "&lang=PT"
  )
  "&Dim2="
  cat("Downloading:", periodo, "...\n")

  # Fazer pedido
  response <- GET(url)

  if (status_code(response) == 200) {
    # Extrair JSON
    dados <- content(response, as = "parsed", encoding = "UTF-8")

    cat("  ✓", length(dados), "registos\n")

    # Adicionar à lista
    todos_dados[[periodo]] <- dados
  } else {
    cat("  ✗ Erro:", status_code(response), "\n")
  }
}

cat("\n")

# =============================================================================
# GUARDAR RESULTADOS
# =============================================================================

if (length(todos_dados) > 0) {
  # Se apenas 1 período, guardar direto
  if (length(PERIODO) == 1) {
    output_file <- paste0("dados_ine_", PERIODO[1], ".json")
    write_json(todos_dados[[1]], output_file, pretty = TRUE, auto_unbox = TRUE)

    cat("✓ Ficheiro guardado:", output_file, "\n")
    cat("  Total de registos:", length(todos_dados[[1]]), "\n\n")

    # Preview
    cat("Preview dos primeiros 5 registos:\n")
    cat(strrep("=", 60), "\n")
    for (i in 1:min(5, length(todos_dados[[1]]))) {
      cat(sprintf(
        "%d. %s: %s €/m²\n",
        i,
        todos_dados[[1]][[i]]$geodsg,
        todos_dados[[1]][[i]]$valor
      ))
    }
  } else {
    # Se múltiplos períodos, guardar cada um separadamente

    cat("Guardando", length(todos_dados), "ficheiros:\n")

    for (periodo in names(todos_dados)) {
      output_file <- paste0("dados_ine_", periodo, ".json")
      write_json(
        todos_dados[[periodo]],
        output_file,
        pretty = TRUE,
        auto_unbox = TRUE
      )
      cat("  ✓", output_file, "-", length(todos_dados[[periodo]]), "registos\n")
    }

    # Também guardar tudo num ficheiro combinado
    output_combined <- paste0(
      "dados_ine_combined_",
      format(Sys.Date(), "%Y%m%d"),
      ".json"
    )
    write_json(todos_dados, output_combined, pretty = TRUE, auto_unbox = TRUE)

    cat("\n✓ Ficheiro combinado:", output_combined, "\n")
    cat("  Estrutura: { 'S7A2025T2': [...], 'S7A2025T1': [...] }\n\n")

    # Preview de cada período
    cat("Preview (primeiros 3 registos de cada período):\n")
    cat(strrep("=", 60), "\n")

    for (periodo in names(todos_dados)) {
      cat("\n", periodo, ":\n")
      for (i in 1:min(3, length(todos_dados[[periodo]]))) {
        cat(sprintf(
          "  %d. %s: %s €/m²\n",
          i,
          todos_dados[[periodo]][[i]]$geodsg,
          todos_dados[[periodo]][[i]]$valor
        ))
      }
    }
  }
} else {
  cat("✗ Nenhum dado foi descarregado\n")
}
