from greeter import Greeter

# don't rewrite greet it is a comment, not a reference
HANDLERS = {"greet": Greeter}


def dispatch(name: str) -> str:
    handler = getattr(Greeter(), "greet")
    return f"calling greet via {handler.__name__}"
