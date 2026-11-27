if [[ "$USE_CN" == "true" ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

# ... local-path early return that never reads REPO_URL ...

remote_head="$(git ls-remote "$REPO_URL" HEAD)"
