if cfg.Endpoint == "" && cfg.LegacyURL != "" {
	cfg.Endpoint = cfg.LegacyURL
}
