if (operation()) {
    return;
}
details::os::sleep_for_millis(100);
if (operation()) {
    return;
}
