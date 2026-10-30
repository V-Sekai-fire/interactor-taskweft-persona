// persona — ask a GTN planning domain for a goal and get an exact plan back.
// Usage: persona <domain.jsonld> <problem.jsonld> [origin ISO-8601 duration]
//        persona --vocabulary <domain.jsonld>
#include "tw_json.hpp"
#include "tw_loader.hpp"
#include "tw_planner.hpp"
#include "tw_temporal.hpp"
#include "tw_explain.hpp"

#include <cstdio>
#include <string>
#include <vector>

static std::string render(const std::vector<TwCall> &plan) {
    std::string s;
    for (size_t i = 0; i < plan.size(); ++i) {
        if (i) s += " -> ";
        s += plan[i].name;
        s += "(";
        for (size_t j = 0; j < plan[i].args.size(); ++j) {
            if (j) s += ", ";
            s += plan[i].args[j].to_string();
        }
        s += ")";
    }
    return s;
}

static void print_goal(const std::vector<TwTask> &tasks) {
    std::printf("goal:");
    for (size_t i = 0; i < tasks.size(); ++i) {
        std::printf(" ");
        std::visit(
            [](const TwTask &task) {
                if (const TwCall *call = std::get_if<TwCall>(&task)) {
                    std::printf("%s(", call->name.c_str());
                    for (size_t j = 0; j < call->args.size(); ++j)
                        std::printf("%s%s", j ? ", " : "", call->args[j].to_string().c_str());
                    std::printf(")");
                } else if (const TwGoal *goal = std::get_if<TwGoal>(&task)) {
                    std::printf("(goal with %zu bindings)", goal->bindings.size());
                } else if (const TwMultiGoal *multi = std::get_if<TwMultiGoal>(&task)) {
                    std::printf("(multigoal with %zu bindings)", multi->bindings.size());
                }
            },
            tasks[i]);
    }
    std::printf("\n\n");
}

// A variable holds a category, a number, or a map of them. The leaves are what
// a goal argument may name, so they print one per line.
static void print_leaves(const std::string &path, const TwValue &value) {
    if (value.is_dict()) {
        for (const std::pair<const std::string, TwValue> &entry : value.as_dict())
            print_leaves(path + "." + entry.first, entry.second);
        return;
    }
    if (value.is_array()) {
        for (size_t i = 0; i < value.as_array().size(); ++i)
            print_leaves(path + "[" + std::to_string(i) + "]", value.as_array()[i]);
        return;
    }
    std::printf("  %-46s %s\n", path.c_str(), value.to_string().c_str());
}

static void print_vocabulary(const TwLoader::TwLoaded &loaded) {
    std::printf("categories and numbers the domain declares:\n");
    for (const std::pair<const std::string, TwValue> &entry : loaded.state->vars)
        print_leaves(entry.first, entry.second);
    for (const std::pair<const std::string, TwValue> &entry : loaded.enums)
        print_leaves("enum " + entry.first, entry.second);

    std::printf("\nactions, with the parameters a call binds:\n");
    for (const std::pair<const std::string, std::vector<std::string>> &entry :
         loaded.domain.action_params) {
        std::printf("  %-30s(", entry.first.c_str());
        for (size_t i = 0; i < entry.second.size(); ++i)
            std::printf("%s%s", i ? ", " : "", entry.second[i].c_str());
        std::printf(")");
        std::unordered_map<std::string, std::string>::const_iterator duration =
            loaded.domain.action_durations.find(entry.first);
        if (duration != loaded.domain.action_durations.end())
            std::printf("  %s", duration->second.c_str());
        std::printf("\n");
    }

    std::printf("\ntasks a goal may ask for:\n");
    for (const std::pair<const std::string, std::vector<TwMethodFn>> &entry :
         loaded.domain.task_methods)
        std::printf("  %s\n", entry.first.c_str());
}

int main(int argc, char **argv) {
    if (argc >= 3 && std::string(argv[1]) == "--vocabulary") {
        const TwLoader::TwLoaded vocabulary = TwLoader::load_file(argv[2]);
        if (!vocabulary.state) {
            std::fprintf(stderr, "persona: could not load domain\n");
            return 2;
        }
        print_vocabulary(vocabulary);
        return 0;
    }
    if (argc < 3) {
        std::fprintf(stderr,
                     "usage: persona <domain.jsonld> <problem.jsonld> [origin ISO-8601 duration]\n"
                     "       persona --vocabulary <domain.jsonld>\n");
        return 2;
    }
    const std::string origin = argc > 3 ? argv[3] : "PT0S";

    TwLoader::TwLoaded loaded = TwLoader::load_file_pair(argv[1], argv[2]);
    if (!loaded.state) {
        std::fprintf(stderr, "persona: could not load domain/problem\n");
        return 2;
    }
    print_goal(loaded.tasks);

    std::optional<std::vector<TwCall>> plan =
        tw_plan(loaded.state, loaded.tasks, loaded.domain);
    if (!plan.has_value()) {
        std::printf("NO PLAN\n%s\n", tw_no_plan_explain_json(loaded.tasks, loaded.domain).c_str());
        return 1;
    }

    const std::string plan_json = TwLoader::plan_to_json(*plan);
    std::printf("PLAN (%zu steps)\n  %s\n\n", plan->size(), render(*plan).c_str());
    std::printf("plan json: %s\n\n", plan_json.c_str());

    const TwTemporalResult temporal = tw_check_temporal(*plan, loaded.domain, origin);
    std::printf("%s\n", tw_temporal_to_json(*plan, temporal, plan_json).c_str());
    return 0;
}
