# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes simple_htn and simple_hgn from GTPyhop's examples (Clear BSD, see LICENSE.txt).
# Run from the repository root: python3 -I tests/gtpyhop/generate_simple.py simple_htn   (or simple_hgn)
# Money is in half-units (cash 20 is 40, the fare 1.5+0.5d is 3+d), so every value is an exact integer.
# An action body here sets constants, so what GTPyhop's ride_taxi and pay_driver compute from the state is computed in
# the method graph and passed as arguments: ride_taxi(p,x,y,fare) and pay_driver(p,y,fare,cash_after). Those extra
# arguments are the one difference from GTPyhop's plan steps; each expected plan is simulated here from GTPyhop's
# methods and checked against the plan GTPyhop returned (recorded/<case>.json) with the extra arguments dropped.
import json,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blocks_lib import *
CASE=sys.argv[1]; D="tests/gtpyhop/"+CASE+"/"
REC=json.load(open("tests/gtpyhop/recorded/"+CASE+".json"))
b2i=lambda g,c: g.r(g.n("type/boolToInt",{"a":c}))
CODE=["alice","bob","taxi1","taxi2","home_a","home_b","park","station"]; IDX={c:i for i,c in enumerate(CODE)}
DIST={("home_a","park"):8,("home_b","park"):2,("station","home_a"):1,("station","home_b"):7,("home_a","home_b"):7,("station","park"):9}
def dist(x,y): return DIST.get((x,y)) or DIST.get((y,x))
def graphTravel():
    g=GB(); p=g.var("p"); y=g.var("y"); x=g.var("x"); d=g.var("d"); fare=g.var("fare"); cash=g.var("cash"); cash2=g.var("cash2")
    foot=g.var("foot"); taxi=g.var("taxi"); G=g.get; I=g.I
    parts=[g.setv(x,g.ptr("/loc/[b]",b=G(p))),g.setv(cash,g.ptr("/cash/[b]",b=G(p))),g.setv(d,I(0))]
    for (a,b),v in DIST.items():
        both=g.or_(g.and_(g.eq(G(x),I(IDX[a])),g.eq(G(y),I(IDX[b]))),g.and_(g.eq(G(x),I(IDX[b])),g.eq(G(y),I(IDX[a]))))
        parts.append(g.branch(both,g.setv(d,I(v))))
    diff=g.not_(g.eq(G(x),G(y)))
    parts+= [g.setv(fare,g.op("math/add",I(3),G(d))),g.setv(cash2,g.op("math/sub",G(cash),G(fare))),
             g.setv(foot,b2i(g,g.and_(diff,g.and_(g.ge(G(d),I(1)),g.op("math/le",G(d),I(2)))))),
             g.setv(taxi,b2i(g,g.and_(diff,g.ge(G(cash),G(fare)))))]
    root(g,g.seq(parts[:10])if len(parts)<=10 else g.seq([g.seq(parts[i:i+10]) for i in range(0,len(parts),10)])); return g.out("travel")
gt=graphTravel(); PP,PY=P("p"),P("y")
def alt(n,f,t): return {"name":n,"graph":gt,"check":[eqc("/graph/"+f,1)],"subtasks":t}
TRAVEL=[{"name":"done","check":[eqc("/loc/[p]",PY)],"subtasks":[]},
        alt("by-foot","foot",[["walk",PP,P("x"),PY]]),
        alt("by-taxi","taxi",[["call_taxi",PP,P("x")],["ride_taxi",PP,P("x"),PY,P("fare")],["pay_driver",PP,PY,P("fare"),P("cash2")]])]
methods={}
if CASE=="simple_htn": TOP="travel"; methods["travel"]={"params":["p","y"],"alternatives":TRAVEL}
else:
    TOP="split"; methods["loc"]={"params":["p","y"],"alternatives":TRAVEL}
    SL=2
    def graphSplit():
        g=GB(); d=[g.var("d%d"%i) for i in range(SL)]; u=[g.var("u%d"%i) for i in range(SL)]; anyv=g.var("any"); parts=[]
        for i in range(SL):
            parts.append(g.setv(d[i],g.ptr("/goal/[b]",b=g.I(i))))
            parts.append(g.setv(u[i],b2i(g,g.and_(g.not_(g.eq(g.get(d[i]),g.I(FREE))),g.not_(g.eq(g.get(d[i]),g.ptr("/loc/[b]",b=g.I(i))))))))
        tot=g.get(u[0])
        for i in range(1,SL): tot=g.op("math/add",tot,g.get(u[i]))
        parts.append(g.setv(anyv,tot)); root(g,g.seq(parts)); return g.out("split")
    sl=GB(); sl_u=sl.var("u"); sl_go=sl.var("go"); root(sl,sl.setv(sl_go,sl.get(sl_u))); slot=sl.out("slot")
    gs=graphSplit()
    methods["slot"]={"params":["x","d","u"],"alternatives":[{"name":"unmet","graph":slot,"check":[ge("/graph/go",1)],"subtasks":[["loc",P("x"),P("d")]]},
                                                           {"name":"met-at-split-time","graph":slot,"check":[eqc("/graph/go",0)],"subtasks":[]}]}
    methods[TOP]={"params":[],"alternatives":[{"name":"achieve-each-then-recheck","graph":gs,"check":[ge("/graph/any",1)],
        "subtasks":[["slot",i,P("d%d"%i),P("u%d"%i)] for i in range(SL)]+[[TOP]]},{"name":"done","graph":gs,"check":[eqc("/graph/any",0)],"subtasks":[]}]}
acts={"walk":{"params":tp("p","x","y"),"body":[eqc("/loc/[p]",P("x")),setp("/loc/[p]",P("y"))]},
      "call_taxi":{"params":tp("p","x"),"body":[setp("/loc/taxi1",P("x")),setp("/loc/[p]","taxi1")]},
      "ride_taxi":{"params":tp("p","x","y")+["fare"],"body":[eqc("/loc/[p]","taxi1"),eqc("/loc/taxi1",P("x")),setp("/loc/taxi1",P("y")),setp("/owe/[p]",P("fare"))]},
      "pay_driver":{"params":tp("p","y")+["fare","cash2"],"body":[eqc("/owe/[p]",P("fare")),ge("/cash/[p]",P("fare")),setp("/cash/[p]",P("cash2")),setp("/owe/[p]",0),setp("/loc/[p]",P("y"))]}}
desc={"simple_htn":"GTPyhop's simple_htn: the task travel(p,y) with the alternatives do_nothing, travel_by_foot, travel_by_taxi in GTPyhop's order. ",
      "simple_hgn":"GTPyhop's simple_hgn: its unigoal methods on loc are the task loc(p,y), with the same three alternatives, and GTPyhop's m_split_multigoal is the task split (two person slots). "}[CASE]
dom={"@context":CTX,"@type":"domain:Definition","name":CASE,"source":"GTPyhop examples/"+CASE,"version":"0.1.0",
 "description":desc+"Money is in half-units: cash 20 is 40 and the taxi fare 1.5+0.5d is 3+d, so every value is an exact integer. ride_taxi and pay_driver take the fare and the cash left as arguments, computed by the method graph, because an action here only sets constants. Distances are the six pairs of GTPyhop's rigid.dist, in both directions.",
 "enums":ENUMS,"variables":[{"name":n,"type":"int","init":{}} for n in ["loc","cash","owe","goal"]],"actions":acts,"methods":methods}
os.makedirs(D,exist_ok=True)
json.dump(dom,open(D+"domain.jsonld","w"),indent=1); open(D+"domain.jsonld","a").write("\n")
# --- simulation of GTPyhop's methods in half-units
def travel(st,p,y,out):
    x=st["loc"][p]
    if x==y: return True
    d=dist(x,y)
    if x!=y and d<=2:
        out.append(("walk",p,x,y)); st["loc"][p]=y; return True
    fare=3+d
    if x!=y and st["cash"][p]>=fare:
        out.append(("call_taxi",p,x)); st["loc"]["taxi1"]=x; st["loc"][p]="taxi1"
        out.append(("ride_taxi",p,x,y,fare)); st["loc"]["taxi1"]=y; st["owe"][p]=fare
        c2=st["cash"][p]-fare
        out.append(("pay_driver",p,y,fare,c2)); st["cash"][p]=c2; st["owe"][p]=0; st["loc"][p]=y; return True
    return False
def sim(st,goals):
    st=json.loads(json.dumps(st)); out=[]
    for p,y in goals:
        if not travel(st,p,y,out): return None
    return out
def gtp(plan): return None if plan is False else [list(a) for a in plan]
def strip(plan):
    out=[]
    for a in map(list,plan):
        if a[0]=="ride_taxi": a=[a[0],a[1],a[3]]
        elif a[0]=="pay_driver": a=a[:3]
        out.append(a)
    return out
S0={"loc":{"alice":"home_a","bob":"home_b","taxi1":"park","taxi2":"station"},"cash":{"alice":40,"bob":30},"owe":{"alice":0,"bob":0}}
def cases():
    ra=lambda s: s  # records: 0 alice to park, 4 both (htn) / 5 multigoal (hgn), last the after-ride state
    after={"loc":{"alice":"park","bob":"home_b","taxi1":"park","taxi2":"station"},"cash":{"alice":29,"bob":30},"owe":{"alice":0,"bob":0}}
    poor=json.loads(json.dumps(S0)); poor["cash"]["alice"]=2
    exact=json.loads(json.dumps(S0)); exact["cash"]["alice"]=11
    both=[("alice","park"),("bob","park")]
    recs=REC
    first=0; second=4 if CASE=="simple_htn" else 5; last=len(recs)-1
    return [("alice-to-park",S0,[("alice","park")],recs[first]["result"]),
            ("alice-then-bob",S0,both,recs[second]["result"]),
            ("alice-already-there",after,[("alice","park")],recs[last]["result"]),
            ("alice-too-poor",poor,[("alice","park")],False),
            ("alice-exact-cash",exact,[("alice","park")],[["call_taxi","alice","home_a"],["ride_taxi","alice","park"],["pay_driver","alice","park"]])]
def mkproblem(name,st,goals,expect):
    vars_=[{"name":"loc","type":"int","init":st["loc"]},{"name":"cash","type":"int","init":st["cash"]},{"name":"owe","type":"int","init":st["owe"]},
           {"name":"goal","type":"int","init":{**{c:"free" for c in CODE},**{p:y for p,y in goals}}}]
    todo=[[TOP]] if CASE=="simple_hgn" and len(goals)>1 else ([["loc",p,y] for p,y in goals] if CASE=="simple_hgn" else [["travel",p,y] for p,y in goals])
    pr={"@context":CTX,"@type":"domain:Problem","name":CASE+"_"+name.replace("-","_"),"domain":CASE,"version":"0.1.0","codebook":CODE,"variables":vars_,
        "capabilities":{"entities":{},"graph":{"edges":[]}},"todo_list":todo}
    json.dump(pr,open(D+name+".problem.jsonld","w"),indent=1); open(D+name+".problem.jsonld","a").write("\n")
    open(D+name+".expect","w").write("\n".join(expect)+("\n" if expect else ""))
names=[]
for name,st,goals,gtpres in cases():
    s=sim(st,goals)
    if gtpres is False:
        assert s is None,name; expect=["REFUSED:unreachable"]
    else:
        assert s is not None and strip(s)==[list(a) for a in gtpres],(name,s,gtpres)
        expect=[a[0]+"("+",".join(map(str,a[1:]))+")" for a in s]
    mkproblem(name,st,goals,expect); names.append(name)
open(D+"cases","w").write("\n".join(names)+"\n")
print(CASE,"ok",len(names))
