library(shiny)
library(DT)

csv_candidates <- c("WDISeries.csv", "WDIseries.csv")
default_csv <- csv_candidates[file.exists(csv_candidates)][1]

read_wdi_series <- function(path) {
  if (is.na(path) || !file.exists(path)) {
    stop("Could not find WDISeries.csv in the app directory.")
  }

  data <- read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("", "NA", "N/A")
  )
  names(data) <- trimws(names(data))
  data[] <- lapply(data, function(column) {
    column <- trimws(column)
    column[column == ""] <- NA_character_
    column
  })
  data
}

if (is.na(default_csv)) {
  stop("Place WDISeries.csv next to app.R before starting the app.")
}

wdi_series <- read_wdi_series(default_csv)
metadata_fields <- names(wdi_series)
categorical_fields <- c("Topic", "Unit of measure", "Periodicity", "Source", "License Type")
categorical_fields <- categorical_fields[categorical_fields %in% metadata_fields]

ui <- fluidPage(
  titlePanel("WDI data availability survey"),
  sidebarLayout(
    sidebarPanel(
      textInput("search", "Search indicators", placeholder = "Name, code, topic, or definition"),
      selectizeInput(
        "topic", "Topic", choices = NULL, multiple = TRUE,
        options = list(plugins = list("remove_button"))
      ),
      selectizeInput(
        "periodicity", "Periodicity", choices = NULL, multiple = TRUE,
        options = list(plugins = list("remove_button"))
      ),
      selectizeInput(
        "source", "Source", choices = NULL, multiple = TRUE,
        options = list(plugins = list("remove_button"))
      ),
      sliderInput("min_completeness", "Minimum metadata completeness", 0, 100, 0),
      checkboxInput("show_definitions", "Include definitions in search", TRUE),
      hr(),
      downloadButton("download", "Download filtered CSV")
    ),
    mainPanel(
      fluidRow(
        column(4, wellPanel(h4("Matching indicators"), textOutput("match_count"))),
        column(4, wellPanel(h4("Metadata completeness"), textOutput("completeness"))),
        column(4, wellPanel(h4("Topics represented"), textOutput("topic_count")))
      ),
      tabsetPanel(
        tabPanel("Indicators", DTOutput("indicator_table")),
        tabPanel(
          "Availability overview",
          h4("Indicators by topic"),
          plotOutput("topic_plot", height = "420px"),
          h4("Indicators by periodicity"),
          plotOutput("periodicity_plot", height = "280px")
        ),
        tabPanel(
          "Metadata quality",
          p("Completeness is the percentage of records with a non-empty value in each metadata field."),
          tableOutput("completeness_table")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  updateSelectizeInput(session, "topic", choices = sort(unique(wdi_series$Topic)), server = TRUE)
  updateSelectizeInput(session, "periodicity", choices = sort(unique(wdi_series$Periodicity)), server = TRUE)
  updateSelectizeInput(session, "source", choices = sort(unique(wdi_series$Source)), server = TRUE)

  filtered_data <- reactive({
    data <- wdi_series

    if (length(input$topic)) {
      data <- data[data$Topic %in% input$topic, , drop = FALSE]
    }
    if (length(input$periodicity)) {
      data <- data[data$Periodicity %in% input$periodicity, , drop = FALSE]
    }
    if (length(input$source)) {
      data <- data[data$Source %in% input$source, , drop = FALSE]
    }

    completeness <- rowMeans(!is.na(data)) * 100
    data <- data[completeness >= input$min_completeness, , drop = FALSE]

    query <- trimws(tolower(input$search))
    if (nzchar(query) && nrow(data)) {
      searchable_fields <- intersect(
        c("Series Code", "Topic", "Indicator Name", "Short definition", "Long definition"),
        names(data)
      )
      if (!isTRUE(input$show_definitions)) {
        searchable_fields <- intersect(c("Series Code", "Topic", "Indicator Name"), names(data))
      }
      matches <- Reduce(`|`, lapply(data[searchable_fields], function(column) {
        grepl(query, tolower(ifelse(is.na(column), "", column)), fixed = TRUE)
      }))
      data <- data[matches, , drop = FALSE]
    }

    data
  })

  output$match_count <- renderText({ format(nrow(filtered_data()), big.mark = ",") })

  output$completeness <- renderText({
    if (!nrow(filtered_data())) return("No matching records")
    paste0(round(mean(rowMeans(!is.na(filtered_data())) * 100), 1), "%")
  })

  output$topic_count <- renderText({
    if (!nrow(filtered_data())) return("0")
    format(length(unique(filtered_data()$Topic)), big.mark = ",")
  })

  output$indicator_table <- renderDT({
    data <- filtered_data()
    columns <- intersect(c("Series Code", "Topic", "Indicator Name", "Unit of measure", "Periodicity", "Source"), names(data))
    datatable(
      data[, columns, drop = FALSE],
      rownames = FALSE,
      filter = "top",
      extensions = "Buttons",
      options = list(
        pageLength = 25,
        lengthMenu = c(10, 25, 50, 100),
        scrollX = TRUE,
        dom = "Bfrtip",
        buttons = c("copy", "csv", "excel")
      ),
      class = "stripe hover compact"
    )
  }, server = TRUE)

  output$topic_plot <- renderPlot({
    counts <- sort(table(filtered_data()$Topic), decreasing = TRUE)
    counts <- head(counts, 20)
    if (!length(counts)) return(plot.new())
    par(mar = c(5, 12, 1, 1))
    barplot(rev(counts), horiz = TRUE, las = 1, col = "#2B6F77",
            xlab = "Number of indicators", cex.names = 0.75)
  })

  output$periodicity_plot <- renderPlot({
    counts <- table(filtered_data()$Periodicity, useNA = "ifany")
    if (!length(counts)) return(plot.new())
    barplot(counts, col = "#D9822B", ylab = "Number of indicators", las = 2)
  })

  output$completeness_table <- renderTable({
    data <- filtered_data()
    if (!nrow(data)) return(data.frame())
    result <- data.frame(
      field = names(data),
      records_with_values = vapply(data, function(column) sum(!is.na(column)), integer(1)),
      completeness_percent = round(vapply(data, function(column) mean(!is.na(column)) * 100, numeric(1)), 1),
      stringsAsFactors = FALSE
    )
    result[order(result$completeness_percent, decreasing = TRUE), ]
  }, striped = TRUE, bordered = TRUE, hover = TRUE)

  output$download <- downloadHandler(
    filename = function() paste0("WDIseries_filtered_", Sys.Date(), ".csv"),
    content = function(file) write.csv(filtered_data(), file, row.names = FALSE, na = "")
  )
}

shinyApp(ui, server)