// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title CertificateChecker
/// @notice Stateless checker for propositional certificates over at most 256 variables: a satisfying
///         assignment of a CNF formula (a certificate that it is satisfiable) and a resolution refutation
///         (a certificate that it is not). The swarm's search and refute work produces both kinds; this lets
///         anyone re-check one without trusting the agent that found it.
/// @dev    Resolution is sound: every clause derived from a formula is true under every assignment that
///         satisfies the formula, so a derivation of the empty clause proves there is none. The checker
///         decides nothing about Lean statements and nothing about P versus NP.
contract CertificateChecker {
    /// @notice A clause: the disjunction of variable i for each bit i of `pos` and of its negation for each
    ///         bit i of `neg`.
    struct Clause {
        uint256 pos;
        uint256 neg;
    }

    /// @notice One resolution step: resolve clause `left`, which holds the pivot variable, with clause
    ///         `right`, which holds its negation. Indices count the formula's clauses first and then the
    ///         clauses derived by earlier steps.
    struct Step {
        uint32 left;
        uint32 right;
        uint8 pivot;
    }

    uint256 public constant MAX_COUNTED_VARIABLES = 20;

    error StepOutOfRange(uint256 step);
    error PivotNotResolvable(uint256 step);
    error TooManyVariables(uint256 numVars);

    /// @notice Whether `assignment` (bit i is the value of variable i) satisfies every clause.
    function satisfies(Clause[] calldata cnf, uint256 assignment) public pure returns (bool) {
        for (uint256 i = 0; i < cnf.length; ++i) {
            if ((cnf[i].pos & assignment) | (cnf[i].neg & ~assignment) == 0) return false;
        }
        return true;
    }

    /// @notice The clauses a derivation produces, one for each step. Reverts on a step that is not a
    ///         resolution step.
    function derive(Clause[] calldata cnf, Step[] calldata steps) public pure returns (Clause[] memory derived) {
        uint256 n = cnf.length;
        derived = new Clause[](steps.length);
        for (uint256 i = 0; i < steps.length; ++i) {
            Step calldata s = steps[i];
            if (s.left >= n + i || s.right >= n + i) revert StepOutOfRange(i);
            Clause memory a = s.left < n ? cnf[s.left] : derived[s.left - n];
            Clause memory b = s.right < n ? cnf[s.right] : derived[s.right - n];
            uint256 bit = uint256(1) << s.pivot;
            if (a.pos & bit == 0 || b.neg & bit == 0) revert PivotNotResolvable(i);
            // Only the pivot leaves the left clause and only its negation leaves the right one. Dropping
            // both polarities from both sides would be unsound when a clause holds the pivot twice over
            // (x or not x, resolved with not x, must leave not x, never the empty clause).
            derived[i] = Clause({pos: (a.pos & ~bit) | b.pos, neg: a.neg | (b.neg & ~bit)});
        }
    }

    /// @notice Whether `steps` is a resolution refutation of `cnf`: a valid derivation whose last clause is
    ///         empty. With no steps, whether the formula itself holds an empty clause.
    function checkRefutation(Clause[] calldata cnf, Step[] calldata steps) external pure returns (bool) {
        if (steps.length == 0) {
            for (uint256 i = 0; i < cnf.length; ++i) {
                if (cnf[i].pos == 0 && cnf[i].neg == 0) return true;
            }
            return false;
        }
        Clause[] memory derived = derive(cnf, steps);
        Clause memory last = derived[derived.length - 1];
        return last.pos == 0 && last.neg == 0;
    }

    /// @notice The number of satisfying assignments over the first `numVars` variables, by exhaustion.
    function countModels(Clause[] calldata cnf, uint256 numVars) external pure returns (uint256 count) {
        if (numVars > MAX_COUNTED_VARIABLES) revert TooManyVariables(numVars);
        uint256 total = uint256(1) << numVars;
        for (uint256 assignment = 0; assignment < total; ++assignment) {
            if (satisfies(cnf, assignment)) ++count;
        }
    }
}
