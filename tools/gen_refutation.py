#!/usr/bin/env python3
"""Generate a resolution refutation of the pigeonhole formula PHP(pigeons, holes), pigeons > holes.

Usage: python3 tools/gen_refutation.py <pigeons> <holes>

Variable x(i, j) = i * holes + j says pigeon i sits in hole j. Clauses, in the order
test/CertificateChecker.t.sol builds them:
  for each pigeon i:                  x(i, 0) or ... or x(i, holes - 1)
  for each hole j and pigeons i < k:  not x(i, j) or not x(k, j)

The refutation is the tree a DPLL search leaves behind: under a partial assignment either a clause is
already false, or the two clauses returned for x = true and x = false are resolved on x. Each step is
printed as five bytes of hex, left index (2), right index (2), pivot (1), where the left clause holds the
pivot and the right clause its negation, as src/CertificateChecker.sol expects. Indices count the
formula's clauses first and then the derived ones. The script only searches; the contract is the judge.
"""
import sys


def php(pigeons, holes):
    clauses = []
    for i in range(pigeons):
        clauses.append((frozenset(i * holes + j for j in range(holes)), frozenset()))
    for j in range(holes):
        for i in range(pigeons):
            for k in range(i + 1, pigeons):
                clauses.append((frozenset(), frozenset((i * holes + j, k * holes + j))))
    return clauses


def refute(clauses, num_vars):
    steps = []
    known = {c: i for i, c in enumerate(clauses)}
    clauses = list(clauses)

    def falsified(assign):
        for idx, (pos, neg) in enumerate(clauses):
            if all(assign.get(v) is False for v in pos) and all(assign.get(v) is True for v in neg):
                return idx
        return None

    def go(assign, var):
        idx = falsified(assign)
        if idx is not None:
            return idx
        if var >= num_vars:
            raise SystemExit("formula is satisfiable: no refutation exists")
        assign[var] = True
        when_true = go(assign, var + 1)
        del assign[var]
        if var not in clauses[when_true][1]:
            return when_true
        assign[var] = False
        when_false = go(assign, var + 1)
        del assign[var]
        if var not in clauses[when_false][0]:
            return when_false
        a, b = clauses[when_false], clauses[when_true]
        resolvent = (frozenset((a[0] | b[0]) - {var}), frozenset((a[1] | b[1]) - {var}))
        if resolvent in known:
            return known[resolvent]
        steps.append((when_false, when_true, var))
        clauses.append(resolvent)
        known[resolvent] = len(clauses) - 1
        return len(clauses) - 1

    last = go({}, 0)
    assert clauses[last] == (frozenset(), frozenset()), "search did not end in the empty clause"
    return steps


def main():
    pigeons, holes = int(sys.argv[1]), int(sys.argv[2])
    steps = refute(php(pigeons, holes), pigeons * holes)
    out = "".join("%04x%04x%02x" % s for s in steps)
    print("steps:", len(steps), file=sys.stderr)
    print(out)


if __name__ == "__main__":
    main()
