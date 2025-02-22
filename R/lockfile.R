
renv_lockfile_init <- function(project) {

  lockfile <- list()

  lockfile$R        <- renv_lockfile_init_r(project)
  lockfile$Python   <- renv_lockfile_init_python(project)
  lockfile$Packages <- list()

  class(lockfile) <- "renv_lockfile"
  lockfile

}

renv_lockfile_init_r_version <- function(project) {

  version <-
    settings$r.version(project = project) %||%
    getRversion()

  format(version)

}

renv_lockfile_init_r_repos <- function(project) {

  repos <- getOption("repos")

  # save names
  nms <- names(repos)

  # force as character
  repos <- as.character(repos)

  # clear RStudio attribute
  attr(repos, "RStudio") <- NULL

  # set a default URL
  repos[repos == "@CRAN@"] <- getOption(
    "renv.repos.cran",
    "https://cloud.r-project.org"
  )

  # remove RSPM bits from URL
  if (config$rspm.enabled()) {
    pattern <- "/__[^_]+__/[^/]+/"
    repos <- sub(pattern, "/", repos)
  }

  # force as list
  repos <- as.list(repos)

  # ensure names
  names(repos) <- nms

  repos

}

renv_lockfile_init_r <- function(project) {
  version <- renv_lockfile_init_r_version(project)
  repos   <- renv_lockfile_init_r_repos(project)
  list(Version = version, Repositories = repos)
}

renv_lockfile_init_python <- function(project) {

  python <- Sys.getenv("RENV_PYTHON", unset = NA)
  if (is.na(python))
    return(NULL)

  if (!file.exists(python))
    return(NULL)

  info <- renv_python_info(python)
  if (is.null(info))
    return(NULL)

  version <- renv_python_version(python)
  type <- info$type
  root <- info$root
  name <- renv_python_envname(project, root, type)

  fields <- list()

  fields$Version <- version
  fields$Type    <- type
  fields$Name    <- name

  fields

}

renv_lockfile_fini <- function(lockfile, project) {
  lockfile$Bioconductor <- renv_lockfile_fini_bioconductor(lockfile, project)
  lockfile
}

renv_lockfile_fini_bioconductor <- function(lockfile, project) {

  # check for explicit version in settings
  version <- settings$bioconductor.version(project = project)
  if (length(version))
    return(list(Version = version))

  # otherwise, check for a package which required Bioconductor
  records <- renv_records(lockfile)
  if (empty(records))
    return(NULL)

  for (package in c("BiocManager", "BiocInstaller"))
    if (!is.null(records[[package]]))
      return(list(Version = renv_bioconductor_version(project = project)))

  sources <- extract_chr(records, "Source")
  if ("Bioconductor" %in% sources)
    return(list(Version = renv_bioconductor_version(project = project)))

  # nothing found; return NULL
  NULL

}

renv_lockfile_path <- function(project) {
  renv_paths_lockfile(project = project)
}

renv_lockfile_save <- function(lockfile, project) {
  file <- renv_lockfile_path(project)
  renv_lockfile_write(lockfile, file = file)
}

renv_lockfile_load <- function(project) {

  path <- renv_lockfile_path(project)
  if (file.exists(path))
    return(renv_lockfile_read(path))

  renv_lockfile_init(project = project)

}

renv_lockfile_sort <- function(lockfile) {

  # ensure C locale for consistent sorting
  renv_scope_locale("LC_COLLATE", "C")

  # extract R records (nothing to do if empty)
  records <- renv_records(lockfile)
  if (empty(records))
    return(lockfile)

  # sort the records
  sorted <- records[sort(names(records))]
  renv_records(lockfile) <- sorted

  # sort top-level fields
  fields <- unique(c("R", "Bioconductor", "Python", "Packages", names(lockfile)))
  lockfile <- lockfile[intersect(fields, names(lockfile))]

  # return post-sort
  lockfile

}

renv_lockfile_create <- function(project, libpaths, type, packages) {

  lockfile <- renv_lockfile_init(project)

  renv_records(lockfile) <-

    renv_snapshot_r_packages(libpaths = libpaths,
                             project  = project) %>%

    renv_snapshot_filter(project = project,
                         type = type,
                         packages = packages) %>%

    renv_snapshot_fixup()

  lockfile <- renv_lockfile_fini(lockfile, project)

  keys <- unique(c("R", "Bioconductor", names(lockfile)))
  lockfile <- lockfile[intersect(keys, names(lockfile))]

  class(lockfile) <- "renv_lockfile"
  lockfile

}

renv_lockfile_modify <- function(lockfile, records) {

  enumerate(records, function(package, record) {
    renv_records(lockfile)[[package]] <<- record
  })

  lockfile

}

renv_lockfile_compact <- function(lockfile) {

  records <- renv_records(lockfile)
  remotes <- map_chr(records, renv_record_format_remote)

  renv_scope_locale("LC_COLLATE", "C")
  remotes <- sort(remotes)

  formatted <- sprintf("  \"%s\"", remotes)
  joined <- paste(formatted, collapse = ",\n")

  all <- c("renv::use(", joined, ")")
  paste(all, collapse = "\n")

}
