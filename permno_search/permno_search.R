# Shiny app for CRSP permno search to get permnos for ghsmart and O'Reilly personality executives
#
# Linux box run from command line: nohup Rscript permno_search.R
# url: aaz.chicagobooth.edu:XXXX where from Listening on http://0.0.0.0:XXXX
#
#----------------------------------------------------------------------------

library(shiny)
library(RPostgreSQL)
library(DT)

# Define UI for application
ui <- fluidPage(
    titlePanel(title="", windowTitle="PERMNO Search App"),

    sidebarLayout(
        sidebarPanel(width=3,
                     textInput("company", "Company name"),
                     br(),
                     actionButton("submit", "Search")
        ),

        mainPanel(
            tabsetPanel(
                tabPanel("PERMNO search", br(), DT::dataTableOutput("table"),
                         br(),
                         downloadButton("download", "Download"))
            )
        )
    )
)

# Define server logic
server <- function(input, output, session) {

    queryResult <- eventReactive(input$submit, {
        input$company
        progress <- Progress$new(session)
        progress$set(message="Retrieving search results . . .", value=5)

        # Query
        isolate({
            con <- dbConnect(PostgreSQL())

            qu <- c("SELECT DISTINCT permno, namedt, nameenddt, cusip, ticker, comnam",
                    " FROM crsp.stocknames",
                    (if (input$company != "") c(" WHERE lower(comnam) LIKE '%", tolower(input$company), "%'")), ";")
            query <- capture.output(cat(qu, sep=""))
            queryResult <- dbGetQuery(con, query)
        })
        progress$close()

        cons <- dbListConnections(PostgreSQL())
        for (coni in cons) {
            dbDisconnect(coni)
        }

        return(queryResult)
    })

    output$table <- DT::renderDataTable(queryResult(), server=TRUE, rownames=FALSE,
                                        options=list(searching=FALSE, lengthMenu = list(c(10, 50, -1), c('10', '50', 'All'))))

    output$download <- downloadHandler("result.csv", content=function(file) {
        rows <- input$table
        write.csv(queryResult(), file, quote=TRUE, col.names=TRUE, row.names=FALSE)
    })
}

shinyApp(ui = ui, server = server, options=list(host = '0.0.0.0'))
