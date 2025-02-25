# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

#' @include record-batch.R
#' @title Table class
#' @description A Table is a sequence of [chunked arrays][ChunkedArray]. They
#' have a similar interface to [record batches][RecordBatch], but they can be
#' composed from multiple record batches or chunked arrays.
#' @usage NULL
#' @format NULL
#' @docType class
#'
#' @section S3 Methods and Usage:
#' Tables are data-frame-like, and many methods you expect to work on
#' a `data.frame` are implemented for `Table`. This includes `[`, `[[`,
#' `$`, `names`, `dim`, `nrow`, `ncol`, `head`, and `tail`. You can also pull
#' the data from an Arrow table into R with `as.data.frame()`. See the
#' examples.
#'
#' A caveat about the `$` method: because `Table` is an `R6` object,
#' `$` is also used to access the object's methods (see below). Methods take
#' precedence over the table's columns. So, `tab$Slice` would return the
#' "Slice" method function even if there were a column in the table called
#' "Slice".
#'
#' @section R6 Methods:
#' In addition to the more R-friendly S3 methods, a `Table` object has
#' the following R6 methods that map onto the underlying C++ methods:
#'
#' - `$column(i)`: Extract a `ChunkedArray` by integer position from the table
#' - `$ColumnNames()`: Get all column names (called by `names(tab)`)
#' - `$nbytes()`: Total number of bytes consumed by the elements of the table
#' - `$RenameColumns(value)`: Set all column names (called by `names(tab) <- value`)
#' - `$GetColumnByName(name)`: Extract a `ChunkedArray` by string name
#' - `$field(i)`: Extract a `Field` from the table schema by integer position
#' - `$SelectColumns(indices)`: Return new `Table` with specified columns, expressed as 0-based integers.
#' - `$Slice(offset, length = NULL)`: Create a zero-copy view starting at the
#'    indicated integer offset and going for the given length, or to the end
#'    of the table if `NULL`, the default.
#' - `$Take(i)`: return an `Table` with rows at positions given by
#'    integers `i`. If `i` is an Arrow `Array` or `ChunkedArray`, it will be
#'    coerced to an R vector before taking.
#' - `$Filter(i, keep_na = TRUE)`: return an `Table` with rows at positions where logical
#'    vector or Arrow boolean-type `(Chunked)Array` `i` is `TRUE`.
#' - `$SortIndices(names, descending = FALSE)`: return an `Array` of integer row
#'    positions that can be used to rearrange the `Table` in ascending or descending
#'    order by the first named column, breaking ties with further named columns.
#'    `descending` can be a logical vector of length one or of the same length as
#'    `names`.
#' - `$serialize(output_stream, ...)`: Write the table to the given
#'    [OutputStream]
#' - `$cast(target_schema, safe = TRUE, options = cast_options(safe))`: Alter
#'    the schema of the record batch.
#'
#' There are also some active bindings:
#' - `$num_columns`
#' - `$num_rows`
#' - `$schema`
#' - `$metadata`: Returns the key-value metadata of the `Schema` as a named list.
#'    Modify or replace by assigning in (`tab$metadata <- new_metadata`).
#'    All list elements are coerced to string. See `schema()` for more information.
#' - `$columns`: Returns a list of `ChunkedArray`s
#' @rdname Table
#' @name Table
#' @export
Table <- R6Class("Table",
  inherit = ArrowTabular,
  public = list(
    column = function(i) Table__column(self, i),
    ColumnNames = function() Table__ColumnNames(self),
    nbytes = function() Table__ReferencedBufferSize(self),
    RenameColumns = function(value) Table__RenameColumns(self, value),
    GetColumnByName = function(name) {
      assert_is(name, "character")
      assert_that(length(name) == 1)
      Table__GetColumnByName(self, name)
    },
    RemoveColumn = function(i) Table__RemoveColumn(self, i),
    AddColumn = function(i, new_field, value) Table__AddColumn(self, i, new_field, value),
    SetColumn = function(i, new_field, value) Table__SetColumn(self, i, new_field, value),
    ReplaceSchemaMetadata = function(new) {
      Table__ReplaceSchemaMetadata(self, new)
    },
    field = function(i) Table__field(self, i),
    serialize = function(output_stream, ...) write_table(self, output_stream, ...),
    to_data_frame = function() {
      Table__to_dataframe(self, use_threads = option_use_threads())
    },
    cast = function(target_schema, safe = TRUE, ..., options = cast_options(safe, ...)) {
      assert_is(target_schema, "Schema")
      assert_that(identical(self$schema$names, target_schema$names), msg = "incompatible schemas")
      Table__cast(self, target_schema, options)
    },
    SelectColumns = function(indices) Table__SelectColumns(self, indices),
    Slice = function(offset, length = NULL) {
      if (is.null(length)) {
        Table__Slice1(self, offset)
      } else {
        Table__Slice2(self, offset, length)
      }
    },
    # Take, Filter, and SortIndices are methods on ArrowTabular
    Equals = function(other, check_metadata = FALSE, ...) {
      inherits(other, "Table") && Table__Equals(self, other, isTRUE(check_metadata))
    },
    Validate = function() Table__Validate(self),
    ValidateFull = function() Table__ValidateFull(self)
  ),
  active = list(
    num_columns = function() Table__num_columns(self),
    num_rows = function() Table__num_rows(self),
    schema = function() Table__schema(self),
    columns = function() Table__columns(self)
  )
)

Table$create <- function(..., schema = NULL) {
  dots <- list2(...)
  # making sure there are always names
  if (is.null(names(dots))) {
    names(dots) <- rep_len("", length(dots))
  }
  stopifnot(length(dots) > 0)

  if (all_record_batches(dots)) {
    return(Table__from_record_batches(dots, schema))
  }

  # If any arrays are length 1, recycle them
  dots <- recycle_scalars(dots)

  Table__from_dots(dots, schema, option_use_threads())
}

#' @export
names.Table <- function(x) x$ColumnNames()

#' @param ... A `data.frame` or a named set of Arrays or vectors. If given a
#' mixture of data.frames and named vectors, the inputs will be autospliced together
#' (see examples). Alternatively, you can provide a single Arrow IPC
#' `InputStream`, `Message`, `Buffer`, or R `raw` object containing a `Buffer`.
#' @param schema a [Schema], or `NULL` (the default) to infer the schema from
#' the data in `...`. When providing an Arrow IPC buffer, `schema` is required.
#' @rdname Table
#' @examplesIf arrow_available()
#' tbl <- arrow_table(name = rownames(mtcars), mtcars)
#' dim(tbl)
#' dim(head(tbl))
#' names(tbl)
#' tbl$mpg
#' tbl[["cyl"]]
#' as.data.frame(tbl[4:8, c("gear", "hp", "wt")])
#' @export
arrow_table <- Table$create
