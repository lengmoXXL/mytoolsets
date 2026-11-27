// check whether the user exists
if _, ok := users[id]; !ok {
	return ErrUserNotFound
}

// GetUserByID returns the user with the given ID.
func GetUserByID(id string) (*User, error) {
