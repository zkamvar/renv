
renv_virtualization_init <- function() {

  `_renv_globals`[["virtualization.type"]] <- tryCatch(
    renv_virtualization_type_impl(),
    error = function(e) "unknown"
  )

}

renv_virtualization_type <- function() {
  `_renv_globals`[["virtualization.type"]]
}

renv_virtualization_type_impl <- function() {

  # only done on linux for now
  if (!renv_platform_linux())
    return("native")

  # check for cgroup
  if (file.exists("/proc/1/cgroup")) {
    contents <- readLines("/proc/1/cgroup")
    if (any(grepl("/docker/", contents)))
      return("docker")
  }

  # assume native otherwise
  "native"

}
