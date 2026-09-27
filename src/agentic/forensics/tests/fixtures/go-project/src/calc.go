package fixture

type Calc struct{}

func (c *Calc) Add(a, b int) int {
	return a + b
}

func (c *Calc) Classify(n int) string {
	if n < 0 {
		return "negative"
	}
	if n == 0 {
		return "zero"
	}
	return "positive"
}

func Pick(n int) int {
	if n > 0 {
		return 1
	}
	return 0
}
