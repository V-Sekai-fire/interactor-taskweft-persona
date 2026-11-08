# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes pyhop_simple_travel_example from GTPyhop's example of that name (Clear BSD, see LICENSE.txt).
# Run from the repository root: python3 -I tests/gtpyhop/generate_travel.py
# Money is in half-units (cash 20 is 40, the fare 1.5+0.5d is 3+d). As in generate_simple.py, ride_taxi and pay_driver take
# the fare and the cash left as arguments, computed by the method graph. The one distance of the example is the variable dist/d.
# GTPyhop's answers for the four problems were taken by running GTPyhop 2.0.2 (commit ca6fa8a) on them.
import json,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blocks_lib import *
CASE="pyhop_simple_travel_example"; D="tests/gtpyhop/"+CASE+"/"
b2i=lambda g,c: g.r(g.n("type/boolToInt",{"a":c}))
CODE=["me","taxi","home","park"]
GTP={"taxi":[["call_taxi","me","home"],["ride_taxi","me","home","park"],["pay_driver","me"]],"poor":False,
     "walk":[["walk","me","home","park"]],"exact":[["call_taxi","me","home"],["ride_taxi","me","home","park"],["pay_driver","me"]]}
def graph():
    g=GB(); a=g.var("a"); d=g.var("d"); fare=g.var("fare"); cash=g.var("cash"); cash2=g.var("cash2"); foot=g.var("foot"); taxi=g.var("taxi"); G=g.get; I=g.I
    root(g,g.seq([g.setv(d,g.ptr("/dist/d")),g.setv(cash,g.ptr("/cash/[b]",b=G(a))),g.setv(fare,g.op("math/add",I(3),G(d))),
        g.setv(cash2,g.op("math/sub",G(cash),G(fare))),g.setv(foot,b2i(g,g.op("math/le",G(d),I(2)))),g.setv(taxi,b2i(g,g.ge(G(cash),G(fare))))]))
    return g.out("travel")
gr=graph()
def alt(n,f,t): return {"name":n,"graph":gr,"check":[eqc("/graph/"+f,1)],"subtasks":t}
methods={"travel":{"params":["a","x","y"],"alternatives":[alt("by-foot","foot",[["walk",P("a"),P("x"),P("y")]]),
  alt("by-taxi","taxi",[["call_taxi",P("a"),P("x")],["ride_taxi",P("a"),P("x"),P("y"),P("fare")],["pay_driver",P("a"),P("fare"),P("cash2")]])]}}
acts={"walk":{"params":tp("a","x","y"),"body":[eqc("/loc/[a]",P("x")),setp("/loc/[a]",P("y"))]},
      "call_taxi":{"params":tp("a","x"),"body":[setp("/loc/taxi",P("x"))]},
      "ride_taxi":{"params":tp("a","x","y")+["fare"],"body":[eqc("/loc/taxi",P("x")),eqc("/loc/[a]",P("x")),setp("/loc/taxi",P("y")),setp("/loc/[a]",P("y")),setp("/owe/[a]",P("fare"))]},
      "pay_driver":{"params":tp("a")+["fare","cash2"],"body":[eqc("/owe/[a]",P("fare")),ge("/cash/[a]",P("fare")),setp("/cash/[a]",P("cash2")),setp("/owe/[a]",0)]}}
dom={"@context":CTX,"@type":"domain:Definition","name":CASE,"source":"GTPyhop examples/"+CASE,"version":"0.1.0",
 "description":"GTPyhop's copy of Pyhop's simple_travel_example: the task travel(a,x,y) with the alternatives travel_by_foot and travel_by_taxi in that order. Money is in half-units: cash 20 is 40 and the fare 1.5+0.5d is 3+d. ride_taxi and pay_driver take the fare and the cash left as arguments, computed by the method graph, because an action here only sets constants. The one distance, home to park, is dist/d.",
 "variables":[{"name":n,"type":"int","init":{}} for n in ["loc","cash","owe","dist"]],"actions":acts,"methods":methods}
os.makedirs(D,exist_ok=True)
json.dump(dom,open(D+"domain.jsonld","w"),indent=1); open(D+"domain.jsonld","a").write("\n")
def sim(cash,d):
    if d<=2: return [("walk","me","home","park")]
    f=3+d
    if cash>=f: return [("call_taxi","me","home"),("ride_taxi","me","home","park",f),("pay_driver","me",f,cash-f)]
    return None
def strip(p): return [list(a[:3]) if a[0]=="ride_taxi" else ([a[0],a[1]] if a[0]=="pay_driver" else list(a)) for a in p]
def strip(p):
    o=[]
    for a in map(list,p):
        if a[0]=="ride_taxi": a=a[:4]
        elif a[0]=="pay_driver": a=a[:2]
        o.append(a)
    return o
CASES=[("taxi",40,8),("poor",4,8),("walk",40,2),("exact",12,9)]
names=[]
for name,cash,d in CASES:
    s=sim(cash,d)
    if GTP[name] is False: assert s is None; expect=["REFUSED:unreachable"]
    else:
        assert s is not None and strip(s)==GTP[name],(name,s); expect=[a[0]+"("+",".join(map(str,a[1:]))+")" for a in s]
    pr={"@context":CTX,"@type":"domain:Problem","name":CASE+"_"+name,"domain":CASE,"version":"0.1.0","codebook":CODE,
        "variables":[{"name":"loc","type":"int","init":{"me":"home","taxi":"park","home":"home","park":"park"}},{"name":"cash","type":"int","init":{"me":cash}},
                     {"name":"owe","type":"int","init":{"me":0}},{"name":"dist","type":"int","init":{"d":d}}],
        "capabilities":{"entities":{},"graph":{"edges":[]}},"todo_list":[["travel","me","home","park"]]}
    json.dump(pr,open(D+name+".problem.jsonld","w"),indent=1); open(D+name+".problem.jsonld","a").write("\n")
    open(D+name+".expect","w").write("\n".join(expect)+"\n"); names.append(name)
open(D+"cases","w").write("\n".join(names)+"\n")
print("ok",len(names))
