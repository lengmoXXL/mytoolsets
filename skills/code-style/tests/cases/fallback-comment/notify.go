func notify(order Order) error {
	// No fallback to SMS: the admin decided against it.
	return email.Send(order.Email, order.Total)
}
