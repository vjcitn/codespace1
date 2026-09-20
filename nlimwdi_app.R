library(shiny)
library(DT)

read_panel <- function(path) {
  data <- read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("", "NA", "N/A")
  )
  names(data) <- trimws(names(data))
  data[] <- lapply(data, function(column) {
    if (is.character(column)) {
      column <- trimws(column)
      column[column == ""] <- NA_character_
    }
    column
  })
  data
}

if (!file.exists("nlimwdi.csv")) {
  stop("Place nlimwdi.csv next to nlimwdi_app.R before starting the app.")
}

wdi <- read_panel("nlimwdi.csv")
year_columns <- names(wdi)[grepl("^[0-9]{4}$", names(wdi))]
years <- as.integer(year_columns)
indicator_catalog <- unique(wdi[c("Indicator Name", "Indicator Code")])

assign_topic <- function(indicator_name, indicator_code) {
  text <- tolower(paste(indicator_name, indicator_code))
  topic_rules <- list(
    "Health" = "health|hospital|mortality|disease|nutrition|immunization|contracept|tuberculosis|malaria|hiv|physician|sanitation|fertility",
    "Education" = "education|school|literacy|enrollment|enrolment|student|teacher|pupil|learning|completion|expenditure on education",
    "Economy and finance" = "gdp|income|poverty|economic|employment|labor|labour|unemployment|wage|trade|export|import|inflation|price|tax|revenue|debt|aid|finance|financial|bank|credit|business|industry|manufactur|service|agriculture",
    "Population and society" = "population|birth|death|fertility|migration|urban|rural|age|gender|women|female|male|social protection|social safety|household|inequality|demographic|refugee",
    "Environment and resources" = "environment|climate|emission|carbon|forest|land|water|energy|electricity|fuel|renewable|biodiversity|air pollution|natural resource|agricultur|crop|food|fertilizer|fish",
    "Infrastructure and technology" = "internet|mobile|telephone|technology|research|patent|computer|transport|road|railway|aviation|port|communication|access to electricity"
  )

  for (topic in names(topic_rules)) {
    if (grepl(topic_rules[[topic]], text, perl = TRUE)) return(topic)
  }
  "Other indicators"
}

indicator_catalog$Topic <- mapply(
  assign_topic,
  indicator_catalog$`Indicator Name`,
  indicator_catalog$`Indicator Code`
)

topic_choices <- sort(unique(indicator_catalog$Topic))
country_choices <- sort(unique(na.omit(wdi$`Country Name`)))
default_countries <- head(country_choices, 5)

ui <- fluidPage(
  titlePanel("WDI time-series explorer"),
  sidebarLayout(
    sidebarPanel(
      selectizeInput(
        "topic", "1. Choose a topic", choices = topic_choices,
        selected = topic_choices[1], options = list(maxOptions = 100)
      ),
      selectizeInput(
        "indicator", "2. Choose an indicator", choices = NULL,
        options = list(maxOptions = 2000)
      ),
      selectizeInput(
        "countries", "Countries or regions", choices = country_choices,
        selected = default_countries, multiple = TRUE,
        options = list(plugins = list("remove_button"), maxOptions = 300)
      ),
      sliderInput(
        "years", "Year range", min = min(years), max = max(years),
        value = c(min(years), max(years)), sep = ""
      ),
      checkboxInput("log_scale", "Use logarithmic y-axis", FALSE),
      hr(),
      downloadButton("download_series", "Download selected series")
    ),
    mainPanel(
      h3(textOutput("selected_indicator")),
      textOutput("coverage_note"),
      plotOutput("series_plot", height = "520px"),
      h4("Selected observations"),
      DTOutput("series_table")
    )
  )
)

server <- function(input, output, session) {
  indicators_in_topic <- reactive({
    indicator_catalog[indicator_catalog$Topic == input$topic, , drop = FALSE]
  })

  observeEvent(indicators_in_topic(), {
    choices <- setNames(
      indicators_in_topic()$`Indicator Code`,
      indicators_in_topic()$`Indicator Name`
    )
    updateSelectizeInput(
      session, "indicator", choices = choices,
      selected = unname(choices[1]), server = TRUE
    )
  }, ignoreInit = FALSE)

  selected_series <- reactive({
    req(input$indicator, input$countries)
    rows <- wdi[
      wdi$`Indicator Code` == input$indicator & wdi$`Country Name` %in% input$countries,
      c("Country Name", "Country Code", "Indicator Name", "Indicator Code", year_columns),
      drop = FALSE
    ]
    if (!nrow(rows)) return(data.frame())

    rows <- rows[, c("Country Name", "Country Code", year_columns), drop = FALSE]
    values <- suppressWarnings(as.numeric(as.matrix(rows[, year_columns, drop = FALSE])))
    long <- data.frame(
      Country = rep(rows$`Country Name`, times = length(years)),
      Country.Code = rep(rows$`Country Code`, times = length(years)),
      Year = rep(years, each = nrow(rows)),
      Value = values,
      stringsAsFactors = FALSE
    )
    long <- long[
      long$Year >= input$years[1] & long$Year <= input$years[2] &
        is.finite(long$Value),
    ]
    long[order(long$Country, long$Year), ]
  })

  output$selected_indicator <- renderText({
    req(input$indicator)
    match <- indicator_catalog[indicator_catalog$`Indicator Code` == input$indicator, ]
    if (!nrow(match)) return("Select an indicator")
    match$`Indicator Name`[1]
  })

  output$coverage_note <- renderText({
    data <- selected_series()
    if (!nrow(data)) return("No observations are available for this selection.")
    paste0(
      nrow(data), " observations across ", length(unique(data$Country)),
      " countries or regions from ", min(data$Year), " to ", max(data$Year), "."
    )
  })

  output$series_plot <- renderPlot({
    data <- selected_series()
    validate(need(
      nrow(data) >= 2,
      "At least two finite observations are required to draw this time series."
    ))
    countries <- unique(data$Country)
    series <- lapply(countries, function(country) {
      values <- data$Value[data$Country == country]
      years_for_country <- data$Year[data$Country == country]
      setNames(values, years_for_country)
    })
    x_range <- input$years
    y_values <- data$Value[data$Value > 0 & is.finite(data$Value)]
    if (isTRUE(input$log_scale)) {
      validate(need(
        length(y_values) >= 2,
        "At least two positive observations are required for a logarithmic plot."
      ))
      plot_limits <- range(y_values)
      if (plot_limits[1] == plot_limits[2]) {
        plot_limits <- plot_limits * c(0.9, 1.1)
      }
      plot(
        x_range, c(plot_limits[1], plot_limits[2]), type = "n", log = "y",
        xlab = "Year", ylab = "Value", main = NULL
      )
    } else {
      plot_limits <- range(data$Value)
      if (plot_limits[1] == plot_limits[2]) {
        padding <- max(abs(plot_limits[1]) * 0.1, 1)
        plot_limits <- plot_limits + c(-padding, padding)
      }
      plot(x_range, plot_limits, type = "n",
           xlab = "Year", ylab = "Value", main = NULL)
    }
    palette <- grDevices::hcl.colors(max(3, length(countries)), "Dark 3")
    for (i in seq_along(countries)) {
      lines(as.integer(names(series[[i]])), series[[i]], col = palette[i], lwd = 2)
    }
    legend("topleft", legend = countries, col = palette[seq_along(countries)],
           lwd = 2, cex = 0.8, bty = "n")
    grid(col = "grey85")
  })

  output$series_table <- renderDT({
    datatable(
      selected_series(), rownames = FALSE, filter = "top",
      options = list(pageLength = 25, scrollX = TRUE),
      class = "stripe hover compact"
    )
  }, server = TRUE)

  output$download_series <- downloadHandler(
    filename = function() paste0("wdi_", input$indicator, ".csv"),
    content = function(file) write.csv(selected_series(), file, row.names = FALSE, na = "")
  )
}

shinyApp(ui, server)