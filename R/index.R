
`_renv_index` <- new.env(parent = emptyenv())

index <- function(scope, key = NULL, value = NULL, limit = 3600L) {

  enabled <- renv_index_enabled(scope, key)
  if (!enabled)
    return(value)

  # resolve variables of interest
  root <- renv_paths_index(scope)
  key <- if (!is.null(key)) renv_index_encode(key)
  now <- as.integer(Sys.time())

  # make sure the directory we're indexing exists
  ensure_directory(root)

  # acquire index lock
  lockfile <- file.path(root, "index.lock")
  renv_scope_lock(lockfile)

  # perform operation
  tryCatch(
    renv_index_impl(root, scope, key, value, now, limit),
    error = function(e) value
  )

}

renv_index_impl <- function(root, scope, key, value, now, limit) {

  # load the index file
  index <- renv_index_load(root, scope)

  # return index as-is when key is NULL
  if (is.null(key))
    return(index)

  # check for an index entry, and return it if it exists
  item <- renv_index_get(root, scope, index, key, now, limit)
  if (!is.null(item))
    return(item)

  # otherwise, update the index
  renv_index_set(root, scope, index, key, value, now, limit)

}

renv_index_load <- function(root, scope) {
  tryCatch(
    expr    = renv_index_load_impl(root, scope),
    error   = function(e) NULL,
    warning = function(e) NULL
  )
}

renv_index_load_impl <- function(root, scope) {

  filebacked(
    scope = paste("index", scope, sep = "."),
    path = file.path(root, "index.json"),
    callback = function(path) {
      tryCatch(
        renv_json_read(path),
        error = function(e) {
          unlink(path)
          list()
        }
      )
    }
  )

}

renv_index_get <- function(root, scope, index, key, now, limit) {

  # check for index entry
  entry <- index[[key]]
  if (is.null(entry))
    return(NULL)

  # see if it's expired
  if (renv_index_expired(entry, now, limit))
    return(NULL)

  # check for in-memory cached value
  value <- `_renv_index`[[scope]][[key]]
  if (!is.null(value))
    return(value)

  # otherwise, try to read from disk
  data <- file.path(root, entry$data)
  if (!file.exists(data))
    return(NULL)

  # read data from disk
  value <- readRDS(data)

  # add to in-memory cache
  `_renv_index`[[scope]] <-
    `_renv_index`[[scope]] %||%
    new.env(parent = emptyenv())

  `_renv_index`[[scope]][[key]] <- value

  # return value
  value

}

renv_index_set <- function(root, scope, index, key, value, now, limit) {

  # write data into index
  data <- tempfile("data-", tmpdir = root, fileext = ".rds")
  ensure_parent_directory(data)
  saveRDS(value, file = data, version = 2L)

  # clean up stale entries
  index <- renv_index_clean(root, scope, index, now, limit)

  # add index entry
  index[[key]] <- list(time = now, data = basename(data))

  # update index file
  path <- file.path(root, "index.json")
  ensure_parent_directory(path)

  # write to tempfile and then copy to minimize risk of collisions
  tempfile <- tempfile(".index-", tmpdir = dirname(path), fileext = ".json")
  renv_json_write(index, file = tempfile)
  file.rename(tempfile, path)

  # return value
  value

}

renv_index_encode <- function(key) {
  text <- deparse(key)
  renv_hash_text(text)
}

renv_index_clean <- function(root, scope, index, now, limit) {

  # figure out what cache entries have expired
  ok <- enum_lgl(
    index,
    renv_index_clean_impl,
    root  = root,
    scope = scope,
    index = index,
    now   = now,
    limit = limit
  )

  # return the existing cache entries
  index[ok]

}

renv_index_clean_impl <- function(key, entry, root, scope, index, now, limit) {

  # check if cache entry has expired
  expired <- renv_index_expired(entry, now, limit)
  if (!expired)
    return(TRUE)

  # remove from in-memory cache
  cache <- `_renv_index`[[scope]]
  cache[[key]] <- NULL

  # remove from disk
  unlink(file.path(root, entry$data))

  FALSE

}

renv_index_expired <- function(entry, now, limit) {
  now - entry$time >= limit
}

renv_index_enabled <- function(scope, key) {
  getOption("renv.index.enabled", default = TRUE)
}
