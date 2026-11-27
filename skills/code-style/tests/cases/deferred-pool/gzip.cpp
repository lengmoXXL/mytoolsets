if (!mPool) {
    mPool = std::make_unique<butil::DelegateSimpleThreadPool>("log-compress", mWorkerCount);
    mPool->Start();
}
