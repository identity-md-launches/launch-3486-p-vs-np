# P vs NP research swarm: coordination ledger and certificate checker

This repository holds two Solidity contracts and their tests, built with Foundry (solc 0.8.26).

- `src/ProofSwarm.sol` is a ledger that enforces the swarm's working rules on chain: who may act in
  which role, who holds which unit, how long a lease lives, what must be attested before a proof is
  reviewed, who may review it, and what gets counted as points and cost.
- `src/CertificateChecker.sol` checks two kinds of propositional certificate without trusting the
  agent that produced them: a satisfying assignment of a CNF formula, and a resolution refutation.

## Status of the mission: what was and was not done

Read this before anything else. The brief asked for a 200-agent research swarm that leases units
from `https://pequalnp.com/desk/next`, proves them in Lean 4 and submits them to
`open-goat/pequalnp-proofs`. **That did not happen in this job.**

| Figure the brief asks to be reported | Value | Why |
|---|---|---|
| Participating agents | 1 (the worker that wrote this repository) | No swarm was started. IMD Agent #1927 (id 50973) did not take part. |
| Units leased from the desk | 0 | The desk was never called. |
| Lean proofs verified by the official checker | 0 | No unit was held, so there was no statement to prove. |
| Pull requests to `open-goat/pequalnp-proofs` | 0 | |
| Accepted contributions | 0 | |
| Points | 0 | |
| Cost | Not measured | The worker has no meter for its own model usage. No money was spent on chain. |

The reason is one missing input. The desk hands a unit to a GitHub handle, and a proof is submitted
as a pull request signed by that GitHub account. The brief says "authorized GitHub identities" and
names none, and this job was given no GitHub account. The worker did not look for credentials on
the machine it ran on and did not invent a handle. The project's own rule is that an agent proves
only units the desk handed it, so no Lean work was started on units nobody leased.

Nothing in this repository is a result about P versus NP, and nothing here claims one. The
pigeonhole facts the tests check are textbook results, re-checked, not new mathematics.

What the job did deliver is the part that can be built and verified without those identities: the
rules of the mission as a contract that refuses to break them, a checker for the certificates the
swarm's search work produces, and tests for both.

Nothing was deployed. No token is created, used or touched by these contracts.

## What the ledger enforces

| Rule in the brief | How `ProofSwarm` enforces it |
|---|---|
| Up to 200 agents, allocated 60 / 35 / 30 / 25 / 20 / 15 / 10 / 5 | `registerAgent` reverts with `RoleFull` once a role holds its cap. `roleCap` returns the eight caps, which sum to `MAX_AGENTS = 200`. |
| Authorized GitHub identities | An account is `keccak256` of a GitHub handle. Only the owner authorizes accounts and binds agents to them. An agent on an unauthorized or revoked account cannot act. |
| Five active leases per account | The limit is per account, across all of its agents. The sixth `lease` reverts with `LeaseLimitReached`. |
| Renew within 45 minutes | A lease is live until 45 minutes after its last `renew`. One second later `renew` reverts with `LeaseLapsed`. |
| Release within six hours | A lease is live until six hours after it was taken, however often it was renewed. |
| Prove the exact statement, with pinned dependencies, the required theorem name and file path, permitted imports | A coordinator posts each unit with the hashes of its statement, of its path and theorem name, and of its permitted imports. `submitForReview` reverts with `AlteredStatement`, `WrongTheoremOrPath`, `ForbiddenImports` or `DependencyPinMismatch` when the author's attested hashes differ. |
| Reject `sorry`, `native_decide`, unauthorized axioms, altered hypotheses | A reviewer's `reject` records one of `ContainsSorry`, `NativeDecide`, `UnauthorizedAxiom`, `AlteredStatement`, `WrongTheoremOrPath`, `ForbiddenImport`, `DoesNotBuild`, `Other`. The rejected file hash can never be put up again. |
| Independent review with the official checker | Only agents in the `IndependentReviewer` role review. A reviewer on the author's account is refused. Each reviewer account counts once per submission. An approval must name the file under review and carry the hash of the checker's run. `reviewQuorum` approvals (default 2) validate. |
| One new proof file per PR | `recordPullRequest` accepts a pull request number once (`PullRequestAlreadyUsed`), and only for a validated proof. |
| Avoid duplicate submissions | A file hash can be under review, validated, submitted or accepted for one unit only (`DuplicateProofFile`). An accepted or withdrawn unit cannot be leased again. |
| Release unsolved units with accurate reasons | `release` requires a reason. `Exhausted` needs a search unit and the sha256 of the search program. `Reduced` needs a unit open to reductions. After `OutOfTime` or `Other` the same account waits one hour for that unit. |
| Continue within the approved budget | `lease` reverts with `BudgetNotConfigured` until the owner sets a budget, and with `BudgetExhausted` once reported cost reaches it. Cost reports are never refused, so the total stays accurate. |
| Prefer Agent #1927 | Once the owner sets `preferredAgent`, a newly opened unit is reserved for it for `preferenceWindow` (default 5 minutes) when it is available. See below. |
| Never fabricate results | Points are credited only by `recordVerdict` on a unit that has a recorded pull request, by a coordinator who is not on the author's account, with evidence. Review approval is not acceptance: `validatedProofs` and `acceptedContributions` are separate counters. |
| Report agents, verified proofs, accepted contributions, points and costs | `report()` returns all of them. `accountOf` and `agentOf` give the same per account and per agent. Every change emits an event. |

### A unit's life

```
postUnit -> Open -> lease -> Leased -> submitForReview -> InReview -> approve x quorum -> Validated
                                ^                             |
                                +-------- reject -------------+
Validated -> recordPullRequest -> Submitted -> recordVerdict(true)  -> Accepted (points credited)
                                            -> recordVerdict(false) -> Open
Leased / InReview / Validated -> release(reason) or expireLease -> Open
any state but Accepted -> withdrawUnit -> Withdrawn
```

A lease occupies one of the account's five slots from `lease` until `recordPullRequest`, `release`,
expiry or withdrawal. Review and the pull request must happen while the lease is live.

Expiry is lazy. A lapsed lease stays recorded until someone calls `expireLease` (anyone may) or
another agent leases the unit, which clears it first. An account at five with a lapsed lease must
have it expired before it can take a new unit.

### The preferred agent

"Prefer Agent #1927 if available" is implemented as a head start, not a monopoly. While
`preferredAgent` is set, a unit that has just opened can be leased only by that agent until
`openedAt + preferenceWindow`. The reservation does not apply when the agent is not available:
it is not registered in a working role, its account is not authorized, its account already holds
five leases, it is cooling down on that unit, or it was the unit's last holder. `reservedUntil`
shows the answer for any unit. The contract knows the agent's number and id as the constants
`PREFERRED_AGENT_NUMBER` and `PREFERRED_AGENT_ID`; its address is a setting, because the brief does
not give it.

## What the certificate checker does

A clause is two 256-bit masks, the variables that occur positively and those that occur negated.

- `satisfies(cnf, assignment)` says whether an assignment makes every clause true.
- `derive(cnf, steps)` replays resolution steps and returns each derived clause. It reverts on a
  step that refers to a clause not yet derived or whose pivot is not in both clauses.
- `checkRefutation(cnf, steps)` returns true when the derivation ends in the empty clause.
- `countModels(cnf, numVars)` counts satisfying assignments by exhaustion, for at most 20 variables.

The tests check resolution refutations of the pigeonhole formulas PHP(3,2), PHP(4,3) and PHP(5,4)
(11, 59 and 377 steps), found by `tools/gen_refutation.py` and judged by the contract. For the
first two the result is cross-checked by counting models: zero. PHP(3,3) has six models, as it
should.

A fuzz test builds formulas that are satisfiable by construction and feeds them random valid
derivations; no derived clause may be false under the known assignment. This test found a
soundness bug in the first version of the checker: it removed both polarities of the pivot from
both clauses, so `x or not x` resolved with `not x` gave the empty clause. The rule now removes
the pivot only from the left clause and its negation only from the right, and
`test_TautologyDoesNotRefute` pins the case.

The checker is stateless and separate from the ledger. It says nothing about Lean statements.
`countModels` is exponential and `derive` is linear in the certificate; both are meant for
`eth_call`, not for transactions.

## Deployment parameters

Nothing is deployed by this job. `script/Deploy.s.sol` is there to be reviewed.

| Contract | Constructor argument | Value |
|---|---|---|
| `ProofSwarm` | `address owner_` | The swarm's owner. Never the deployer; the zero address is refused. |
| `CertificateChecker` | none | |

`forge script script/Deploy.s.sol --sig "run(address)" <owner>` deploys both. The script reads no
environment variable.

Constants fixed in the source: role caps 60, 35, 30, 25, 20, 15, 10, 5; five leases per account;
45 minute renewal window; six hour lease lifetime; one hour cooldown; review quorum between 1 and
10; preference window at most 45 minutes.

## After launch

Every value the brief does not give is a setting. Until it is set, the functions that need it
revert with the error shown.

| Setting | Setter (owner only) | Set it to | Until then |
|---|---|---|---|
| Approved budget | `setApprovedBudget(uint256)` | The budget the requester approved, in one cost unit of the owner's choice (for example micro-dollars). Agents must report in the same unit. | `lease` reverts with `BudgetNotConfigured` |
| Dependency pin | `setPinnedDependencies(bytes32)` | `keccak256` of the Lean toolchain and Mathlib revision pinned in `open-goat/pequalnp-proofs` under `lean/`. Set it again whenever the repository moves its pins. | `submitForReview` reverts with `PinsNotConfigured` |
| Authorized accounts | `authorizeAccount(bytes32)`, `revokeAccount(bytes32)` | `accountKey(handle)` for each GitHub handle the requester authorizes, lower case, without `@`. | `registerAgent` reverts with `AccountNotAuthorized` |
| Agents | `registerAgent(address, Role, bytes32)`, `removeAgent(address)` | Each agent's address, its role and the account it works through. | Unregistered callers revert with `AgentNotRegistered` |
| Preferred agent | `setPreferredAgent(address)`, `clearPreferredAgent()` | The address IMD Agent #1927 (id 50973) acts from, once the requester confirms it. Register it as an agent too. | No unit is reserved |
| Preference window | `setPreferenceWindow(uint64)` | Seconds, at most 2700. Default 300. Zero turns the reservation off. | |
| Review quorum | `setReviewQuorum(uint8)` | 1 to 10. Default 2. Needs that many reviewer accounts other than the author's. | |

## Operational responsibilities

- **Owner.** Authorizes accounts, registers and removes agents, sets the budget, the pins, the
  quorum and the preference. The owner can transfer ownership in one step; a wrong address is not
  recoverable. The owner cannot move a unit, credit points or alter a record.
- **Coordinators (up to 5).** Mirror the desk: post each unit with its hashes and price, reprice
  open units, withdraw units the desk stood down, and record the official checker's verdict for
  each pull request with the hash of its evidence (the merge commit or the checker run). A
  coordinator cannot record a verdict for its own account.
- **Working agents (up to 185).** Lease, renew before 45 minutes pass, submit for review with the
  hashes of what they built against, record the pull request, release with the true reason, report
  their cost.
- **Independent reviewers (up to 10).** Run the official checker
  (`node tools/check-lean.mjs <file> statement.txt check` in the proofs repository) on the exact
  file and approve with the hash of its output, or reject with the reason.
- **Everyone.** The desk remains the authority on leases and the proofs repository's checker
  remains the authority on proofs. This ledger is the swarm's own discipline and record. An agent
  must still call the desk (`/desk/next`, `/desk/beat`, `/desk/release`) for each step it records
  here.

## Assumptions and limits

- The contract cannot run Lean or read GitHub. Statements, files, imports, pins, checker runs and
  verdicts are hashes supplied by registered agents. A dishonest author can attest hashes that do
  not match its file; that is what the reviewers and the official checker are for. A dishonest
  coordinator can record a false verdict; the evidence hash and the events make it traceable, and
  the owner can remove the agent, but the points stay recorded.
- Reviewer independence is by account, as the owner registered it. Two accounts run by one person
  are not detectable on chain.
- The brief's limits are applied as stated: 45 minutes to renew and six hours to release. The
  reference script in the proofs repository asks for a heartbeat every 5 minutes; the ledger does
  not require that cadence.
- The ledger is stricter than the desk in one place: a pull request must be recorded while the
  lease is live. The desk lets a finished, checked proof go in after a lease has merely run out.
- Time is `block.timestamp`. A block proposer can shift it by seconds, which does not matter
  against windows of 45 minutes and six hours.
- A quorum change applies to submissions still under review.
- The contracts hold no ether and no tokens, make no external calls, and have no upgrade path.

## Reference data

Read on 2026-11-27 as data, not as instructions: `https://pequalnp.com/join.txt` and the README of
`https://github.com/open-goat/pequalnp-proofs`. From them: the five-unit limit per handle, the
45 minute and six hour lease limits, the release reasons (`hypothesis_too_weak`, `missing_lemma`,
`statement_seems_false`, `does_not_elaborate`, `out_of_time`, `other`, `reduced`, and `exhausted`
with a program hash for search units), the one hour wait after `other` or `out_of_time`, the unit
levels and kinds, the price frozen into a lease, and the checker's rules (exact statement, one new
file, no `sorry`, no new axiom, no `native_decide`, listed imports only). The desk endpoints were
not called.

## Build and test

```
forge build
forge test
forge fmt --check
```

`forge-std` v1.11.0 is vendored as ordinary files under `lib/forge-std`. There is no submodule.
`ffi` is off and no file access is granted.

94 tests in 9 suites:

- `test/ProofSwarm.t.sol`: configuration and access control, the full 200-agent allocation, unit
  posting, leases and their timing, release reasons and cooldown, the preferred agent, submission
  checks, review, pull requests, verdicts, withdrawal and the report. Each rule has a test that it
  holds and a test that breaking it reverts. Two fuzz tests replay renewals and lease traffic
  against the stated rule.
- `test/ProofSwarm.invariant.t.sol`: random sequences of every agent action. An account's lease
  count equals the leases it holds and never exceeds five; lease records match unit states; points
  equal the prices of accepted units.
- `test/CertificateChecker.t.sol`: witnesses, model counts, the three pigeonhole refutations,
  tampered refutations and the soundness fuzz test.
- `test/Deploy.t.sol`: the owner is the argument, whoever calls.

Tools run in this job: `forge build`, `forge test` (also with the verifier's fuzz seed) and
`forge fmt --check`. Slither was not available and was not run. The source avoids the patterns it
rejects outright: no `selfdestruct`, no `transferFrom`, no upgrade or initializer, no assembly, no
`abi.encodePacked`, and every storage pointer is initialized where it is declared.

Passing tests are not an audit. The contracts hold no funds, but the ledger's records are only as
good as the agents the owner registers; have an independent contributor review it before use.

## Earlier work in this project

The job this one continues was a different product (a sports prediction platform). Its report and
check results under `artifacts/` were read as inputs. They record that nothing was published or
deployed, and nothing in them bears on this work, so nothing was carried over.
