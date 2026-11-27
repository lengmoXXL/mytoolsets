if (mBackends) {
    if (path.empty()) {
        return Status::OK();
    }
    return Status(EALREADY, "Logging system already initialized");
}
