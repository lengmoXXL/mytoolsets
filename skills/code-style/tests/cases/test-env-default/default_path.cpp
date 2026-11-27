if (const auto *testDir = std::getenv("TEST_TMPDIR")) {
    defaultPath = std::filesystem::path(testDir) / defaultPath.filename();
}
