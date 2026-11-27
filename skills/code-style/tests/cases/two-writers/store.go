type store struct{ path string }

func (s *store) Save(v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0o644)
}

func (s *store) Dump(v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0o644)
}
