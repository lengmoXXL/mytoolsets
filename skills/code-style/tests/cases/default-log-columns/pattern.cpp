// An omitted ColumnNames uses time, level, thread and source location.
// The first message field supplies the tab after the default source column.
std::string MakePattern(const std::vector<std::string_view> &selectedColumns)
{
    const bool useDefaultColumns = selectedColumns.empty();
    std::string pattern;
    for (const auto &[column, flag] : {
            std::pair{"__TIME__", "[%Y-%m-%d %H:%M:%S.%f]\t"},
            std::pair{"__LEVEL__", "[%Q]\t"},
            std::pair{"__THREAD__", "[%t]\t"},
            std::pair{"__FILE__", "[%g:%#]\t"},
            std::pair{"__LOGGER__", "[%n]\t"},  // New option for explicit selection.
         }) {
        if (useDefaultColumns ||
            std::find(selectedColumns.begin(), selectedColumns.end(), column) != selectedColumns.end()) {
            pattern.append(flag);
        }
    }
    if (useDefaultColumns) {
        pattern.pop_back();
    }
    pattern.append("%v");
    return pattern;
}