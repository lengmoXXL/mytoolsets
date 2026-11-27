// internal/httpapi/checkout.go
func PlaceOrder(w http.ResponseWriter, r *http.Request) {
	cart := cart.Load(r.FormValue("cart_id"))

	subtotal := pricing.Subtotal(cart.Items())
	subtotal -= pricing.Coupon(cart.Items(), r.FormValue("coupon"))
	total := pricing.Tax(subtotal)

	charge, err := payment.Charge(r.FormValue("token"), total)
	if err != nil {
		http.Error(w, "payment failed", http.StatusBadGateway)
		return
	}
	order := order.New(cart.Items(), total, charge.ID)
	order.Save()
	json.NewEncoder(w).Encode(order)
}
