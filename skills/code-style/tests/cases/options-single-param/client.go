type Option func(*client)

func WithTimeout(d time.Duration) Option {
	return func(c *client) { c.timeout = d }
}

func New(addr string, opts ...Option) *client {
	c := &client{addr: addr, timeout: 30 * time.Second}
	for _, opt := range opts {
		opt(c)
	}
	return c
}
