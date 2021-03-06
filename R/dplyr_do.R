#' @export
do_.tbl_spark <- function(.data, ..., .dots) {
  sdf <- spark_dataframe(.data)

  # get column references to grouped variables
  groups <- as.character(as.list(dplyr::groups(.data)))
  columns <- lapply(groups, function(group) {
    invoke(sdf, "col", group)
  })

  # compute unique combinations of values
  combos <- sdf %>%
    invoke("select", columns) %>%
    invoke("groupBy", columns) %>%
    invoke("count") %>%
    sdf_collect() %>%
    select(-count)

  # apply function on subsets of data
  outputs <- vector("list", nrow(combos))
  nm <- names(combos)

  lapply(seq_len(nrow(combos)), function(i) {

    # generate filters for each combination
    filters <- lapply(seq_along(nm), function(j) {
      sdf %>%
        invoke("col", nm[[j]]) %>%
        invoke("equalTo", combos[[j]][[i]])
    })

    # apply filters
    filtered <- sdf
    for (filter in filters)
      filtered <- invoke(filtered, "filter", filter)

    # apply functions with this data
    fits <- enumerate(.dots, function(name, lazy) {

      # override '.' in envir
      assign(".", filtered, envir = lazy$env)

      # munge call (add '.' as the first argument if not specified)
      if (sparklyr_boolean_option("sparklyr.do.implicit.dot")) {
        dot <- as.name(".")
        found <- Find(function(x) identical(x, dot), lazy$expr)
        if (is.null(found)) {
          replacement <- vector("list", length(lazy$expr) + 1)
          replacement[[1]] <- lazy$expr[[1]]
          replacement[[2]] <- dot
          for (i in seq_len(length(lazy$expr) - 1))
            replacement[[i + 2]] <- lazy$expr[[i + 1]]
          lazy$expr <- as.call(replacement)
        }
      }

      # evaluate in environment
      tryCatch(
        eval(lazy$expr, envir = lazy$env),
        error = identity
      )

    })

    # store
    outputs[[i]] <<- fits

  })

  # produce 'result' dataset by adding outputs to 'combos'
  result <- combos
  columns <- lapply(names(.dots), function(name) {
    lapply(outputs, `[[`, name)
  })

  for (i in seq_along(.dots)) {
    key <- names(.dots)[[i]]
    val <- lapply(outputs, `[[`, key)
    result[[key]] <- val
  }

  result

}
