package fixture;

public class Calc {
    public int add(int a, int b) {
        return a + b;
    }

    public String classify(int n) {
        if (n < 0) {
            return "negative";
        }
        if (n == 0) {
            return "zero";
        }
        return "positive";
    }
}
