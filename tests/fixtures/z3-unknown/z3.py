"""z3-tla-playbook template の unknown 分類を依存なしで検査する fake binding。"""

sat = object()
unsat = object()
unknown = object()


class Expr:
    def __ge__(self, other):
        return self

    def __le__(self, other):
        return self

    def __lt__(self, other):
        return self


def Int(name):
    return Expr()


def And(*args):
    return Expr()


def Or(*args):
    return Expr()


def Not(arg):
    return Expr()


class Solver:
    def add(self, *args):
        return None

    def check(self):
        return unknown

    def reason_unknown(self):
        return "fixture-forced-unknown"
