class Counter:
    def __init__(self):
        self.value = 0

    def bump(self):
        self.value += 1
        return self.value
