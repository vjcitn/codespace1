# WDI Time-Series Explorer

This document describes the software in `nlimwdi_app.R`, a Shiny application for exploring the time series in `nlimwdi.csv`. The application lets a user choose a topical group, choose an indicator within that group, select countries or regions, inspect a time-series plot, filter the observations table, and download the selected observations.

## Application Files

- `nlimwdi_app.R`: Shiny user interface, data preparation, server logic, plotting, table rendering, and download handler.
- `nlimwdi.csv`: Wide World Bank-style data file containing country/region metadata, indicator metadata, and annual columns.

The current file contains 1,498 indicators, 265 country or region labels, and annual observations from 1960 through 2025. The application expects the CSV to remain in the same working directory as the R script.

## Data Wrangling

### Import and cleaning

The `read_panel()` function imports the CSV with base R's `read.csv()` and preserves the original column names. It treats empty strings, `NA`, and `N/A` as missing values, trims whitespace from names and character values, and converts empty character values to `NA`.

The script identifies year columns by matching four-digit column names. This avoids hard-coding the number of years and allows the application to continue working if future extracts add or remove annual columns.

### Indicator catalog

The application creates an indicator catalog from the unique combinations of `Indicator Name` and `Indicator Code`. This catalog is used for the cascading controls rather than repeatedly deriving indicator choices from the full country-level panel.

Indicator codes are the internal values used by the selector because they are stable identifiers. Indicator names are displayed to users because they are more understandable than codes.

### Topic assignment

The source file does not contain a topic column. The `assign_topic()` function therefore assigns each indicator to a topic using case-insensitive regular expressions applied to the indicator name and code. The current groups are:

- Health
- Education
- Economy and finance
- Population and society
- Environment and resources
- Infrastructure and technology
- Other indicators

Rules are evaluated in order, and the first matching topic wins. Indicators that match no rule are placed in `Other indicators`, ensuring that all available indicators remain selectable.

### Wide-to-long conversion

The selected country rows are extracted from the wide panel. Their year columns are converted to numeric values and reshaped into a long table with `Country`, `Country.Code`, `Year`, and `Value` columns. Missing, infinite, and negative-infinite values are removed before the table or plot is generated.

## Interactive UI Design

The interface uses a sidebar and main-panel layout:

1. The user selects a topic.
2. The indicator selector is updated to contain only indicators in that topic.
3. The user selects one or more countries or regions.
4. The user chooses a year range and optionally enables a logarithmic y-axis.
5. The main panel displays the selected indicator, coverage information, a line plot, and a DT data table.

The topic-to-indicator cascade is implemented with a reactive expression and `observeEvent()`. When the topic changes, `updateSelectizeInput()` replaces the indicator choices and selects the first available indicator in the new topic.

The observations table uses `DT::DTOutput()` and `DT::renderDT()`. It supports client-side column filtering, sorting, pagination, and horizontal scrolling. The download button writes the current selected series to a CSV file.

### Plot safeguards

The plot uses `validate(need())` to avoid confusing base R errors for sparse indicators. It requires at least two finite observations. Logarithmic plots additionally require at least two positive observations. Constant series receive a small y-axis expansion so they can still be displayed.

## Running the Application

From the directory containing `nlimwdi_app.R` and `nlimwdi.csv`:

```r
install.packages(c("shiny", "DT"), repos = "https://cloud.r-project.org")
shiny::runApp("nlimwdi_app.R")
```

Alternatively, from a shell:

```bash
Rscript -e 'shiny::runApp("nlimwdi_app.R")'
```

The app can also be run from RStudio or VS Code by opening the script and using the Shiny run command. The working directory must contain the CSV, unless the path handling is changed.

## Deployment

### Local or Codespace deployment

Local execution is the simplest deployment mode. In a Codespace, start the app with an exposed port if the environment requests one. Use the URL supplied by the Codespace or forward the Shiny port through VS Code.

### shinyapps.io

For hosted deployment, install `rsconnect`, authenticate with a shinyapps.io account, and deploy the directory containing the app and CSV:

```r
install.packages("rsconnect", repos = "https://cloud.r-project.org")
rsconnect::setAccountInfo(
  name = "ACCOUNT_NAME",
  token = "TOKEN",
  secret = "SECRET"
)
rsconnect::deployApp(".", appPrimaryDoc = "nlimwdi_app.R")
```

Credentials should be supplied through the deployment setup and should not be committed to the repository. The CSV is uploaded with the application because the script reads it at startup.

### Container or server deployment

A production deployment could package R, Shiny, DT, the script, and the CSV in a container, then serve the app through Shiny Server or another supported hosting platform. This is useful when reproducible system dependencies, private data, authentication, or resource limits are important.

## Decisions That Could Be Revised

### Keyword-based topics

The current topic taxonomy is deliberately lightweight and transparent, but it is not a formal World Bank classification. Some indicators can match multiple concepts, and rule order determines their final topic. For example, agriculture-related indicators may be classified under Economy and finance before Environment and resources because of the current rule order.

Possible revisions include:

- Maintain an explicit indicator-code-to-topic mapping file.
- Use a curated taxonomy reviewed by subject-matter experts.
- Use the indicator metadata catalog as the source of official groups if a categorized extract becomes available.
- Allow an indicator to belong to multiple topics.

### Default countries

The app selects the first five alphabetically sorted country or region labels. This is predictable but not necessarily useful for every audience. Defaults could instead be configured as a named set, such as a user's home countries, a region, or a global comparison group.

### Plot implementation

The plot uses base R for minimal dependencies and straightforward rendering. It could be replaced with `ggplot2`, `plotly`, or another interactive charting library to provide hover values, richer legends, and zooming. More countries may require a better legend strategy or a country-selection limit.

### Data loading

The complete panel is loaded into memory when the app starts. This is acceptable for the current file but may become slow as the number of indicators, countries, or years grows. The app could use `data.table`, Arrow, DuckDB, or a database-backed reactive query for larger extracts.

### Missing values

Missing values are omitted from the plot and table. This keeps the output readable but does not distinguish between unavailable observations, structural missingness, and values suppressed by the source. A future version could display gaps explicitly and provide a missingness summary by country and year.

## Opportunities for Improvement

1. **Improve classification quality.** Add a reviewable topic mapping table and tests for representative indicators in every group.
2. **Add indicator metadata.** Show the indicator definition, unit of measure, source, and notes from a companion metadata file when available.
3. **Improve country discovery.** Add region filters, country search, presets, and a maximum number of plotted countries.
4. **Add availability diagnostics.** Show the number and percentage of nonmissing values by country, year, and indicator before plotting.
5. **Improve charts.** Add hover tooltips, selectable series, smoother color handling, and an option to normalize or index values.
6. **Support more data shapes.** Accept a long-format input as well as the current wide format, with explicit schema validation and a clearer error message for malformed files.
7. **Add automated tests.** Test CSV loading, year detection, topic assignment, cascading choices, sparse-series validation, constant series, and download output.
8. **Improve reproducibility.** Add a package lockfile such as `renv.lock`, record the source-data release, and document the R version used for deployment.
9. **Harden deployment.** Add resource limits, logging, authentication where required, and a deployment configuration for the selected hosting platform.
10. **Separate concerns.** Move data preparation and topic rules into functions or separate R files so the UI and server logic are easier to maintain.

## Current Limitations

- Topics are inferred from text rather than supplied by the source.
- The app assumes the input file has the expected World Bank-style column names.
- The app uses a local relative path for the data file.
- There is no authentication or access control.
- The plot is not interactive beyond Shiny input changes.
- There is no formal automated test suite.