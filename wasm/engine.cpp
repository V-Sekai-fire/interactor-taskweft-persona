// The RECTGTN engine in the browser: a domain and a problem in, the plan out.
// The planner is the vendored engine (tw_loader.hpp, tw_planner.hpp); this file only
// loads the pair the way TwLoader::load_file_pair does, from strings, and calls tw_plan.
#include "tw_loader.hpp"
#include "tw_planner.hpp"
#include <cstring>
#include <exception>
#include <string>

static std::string answer;

static const char *refuse(const char *why) {
  answer = std::string("{\"refused\":\"") + why + "\"}";
  return answer.c_str();
}

extern "C" const char *persona_engine_plan(const char *domain, const char *problem) {
  try {
    TwLoader::TwLoaded dom = TwLoader::load_json(domain);
    if (!dom.state) return refuse("bad_domain");
    // The engine's loader refuses any top-level key it does not know. A problem document names its
    // domain under "domain", which the loader does not list, so that one key is dropped first.
    TwValue pv = TwLoader::parse_json_str(problem);
    if (pv.is_dict()) {
      TwValue::Dict pd = pv.as_dict();
      pd.erase("domain");
      pv = TwValue(pd);
    }
    TwLoader::TwLoaded prob = TwLoader::load_domain(pv);
    if (!prob.state) return refuse("bad_problem");
    for (auto &[k, v] : prob.state->vars) dom.state->vars[k] = v;
    for (auto &[k, v] : prob.domain.task_methods) dom.domain.task_methods[k] = v;
    for (auto &[k, v] : prob.domain.actions) dom.domain.actions[k] = v;
    if (!prob.tasks.empty()) dom.tasks = prob.tasks;
    if (dom.tasks.empty()) return refuse("no_goal");
    auto plan = tw_plan(dom.state, dom.tasks, dom.domain);
    if (!plan) return refuse("unreachable");
    answer = "{\"plan\":" + TwLoader::plan_to_json(*plan) + ",\"engine\":\"rectgtn\"}";
    return answer.c_str();
  } catch (const std::exception &e) {
    answer = std::string("{\"refused\":\"engine_error\",\"detail\":\"") + e.what() + "\"}";
    return answer.c_str();
  }
}
