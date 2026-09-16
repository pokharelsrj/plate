package handlers

// jacksonPollock3Site returns body fat % using the Jackson-Pollock 3-site formula for men
// (chest, abdomen, thigh). All measurements in mm.
func jacksonPollock3Site(age int, chest, abdomen, thigh float64) float64 {
	sum := chest + abdomen + thigh
	db := 1.10938 - 0.0008267*sum + 0.0000016*sum*sum - 0.0002574*float64(age)
	if db <= 0 {
		return 0
	}
	return 495.0/db - 450.0
}
