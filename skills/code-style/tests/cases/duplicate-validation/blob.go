type blob struct{ path string }

func Load(path string) ([]byte, error) {
	if path == "" {
		return nil, errors.New("empty path")
	}
	return os.ReadFile(path)
}

func (b *blob) Read() ([]byte, error) {
	if b.path == "" {
		return nil, errors.New("empty path")
	}
	return Load(b.path)
}
