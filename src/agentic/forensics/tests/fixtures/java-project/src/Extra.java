package fixture;

import java.util.List;

public class Extra {
    public int sum(List<Integer> values) {
        int total = 0;
        for (Integer value : values) {
            if (value != null) {
                total += value;
            }
        }
        return total;
    }

    public Runnable task(final int limit) {
        return () -> {
            if (limit > 0) {
                System.out.println(limit);
            }
        };
    }

    public Runnable anonymous(final int limit) {
        return new Runnable() {
            @Override
            public void run() {
                if (limit > 0) {
                    System.out.println(limit);
                }
            }
        };
    }
}
