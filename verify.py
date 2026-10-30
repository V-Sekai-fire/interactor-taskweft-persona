#!/usr/bin/env python3
# Runs the planner's differential fixtures through the persona binary and
# counts what it solved. The pairing comes from the repository's own
# fixtures/expected/ names (domain__problem), so nothing is guessed.
# The control asks for a task the domain does not declare: a check that cannot
# report NO PLAN certifies nothing.
import argparse
import glob
import os
import subprocess
import sys

CONTROL = """{
  "@context": {"vsekai": "https://v-sekai.org/", "domain": "vsekai:planning/domain/"},
  "@type": "domain:Problem",
  "name": "control",
  "variables": [{"name": "at", "init": {"robot_1": "dock"}}],
  "todo_list": [["teleport_pkg", "robot_1", "package_9"]]
}"""


def cases(fixtures):
    pairs = []
    singles = []
    for expected in sorted(glob.glob(f"{fixtures}/expected/*_expected.json")):
        stem = os.path.basename(expected)[: -len("_expected.json")]
        if "__" not in stem:
            singles.append(stem)
            continue
        domain, _, problem = stem.partition("__")
        pairs.append((domain, problem))
    return pairs, singles


def run(persona, domain_path, problem_path):
    result = subprocess.run(
        [persona, domain_path, problem_path], capture_output=True, text=True, timeout=60
    )
    if "PLAN (" in result.stdout:
        return int(result.stdout.split("PLAN (")[1].split(" steps)")[0]), result.stdout
    return None, result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--planner", default="../rectgtn-domain-c-abi")
    parser.add_argument("--persona", default="./persona")
    args = parser.parse_args()

    fixtures = f"{args.planner}/test/differential/fixtures"
    if not os.path.isdir(fixtures):
        print(f"FAIL no fixtures at {fixtures}")
        return 1
    pairs, singles = cases(fixtures)
    if not pairs:
        print(f"FAIL no expected fixtures under {fixtures}/expected")
        return 1
    print(f"not a domain/problem pair, not run here: {', '.join(singles) if singles else 'none'}")

    solved, refused, errors, total_steps = 0, 0, 0, 0
    for domain, problem in pairs:
        domain_path = f"{fixtures}/domains/{domain}.jsonld"
        problem_path = f"{fixtures}/problems/{problem}.jsonld"
        if not os.path.exists(domain_path) or not os.path.exists(problem_path):
            errors += 1
            print(f"FAIL missing fixture pair {domain}__{problem}")
            continue
        steps, text = run(args.persona, domain_path, problem_path)
        if steps is None:
            if "NO PLAN" in text:
                refused += 1
            else:
                errors += 1
                print(f"FAIL {problem}: {text.strip()[:120]}")
        else:
            solved += 1
            total_steps += steps

    control_domain = f"{args.planner}/bench/fixtures/domains/warehouse_domain.jsonld"
    control_path = "/tmp/persona-control.jsonld"
    with open(control_path, "w") as handle:
        handle.write(CONTROL)
    _, control_text = run(args.persona, control_domain, control_path)
    control_ok = "NO PLAN" in control_text
    print(f"control (undeclared task): {'NO PLAN' if control_ok else 'FAILED TO REFUSE'}")

    print(
        f"solved={solved} refused={refused} errors={errors} steps={total_steps} "
        f"of {len(pairs)} enumerated cases"
    )
    if errors or not control_ok or solved == 0:
        print("FAIL")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
