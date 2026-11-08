# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes blocks_hgn and blocks_goal_splitting from GTPyhop's examples (Clear BSD, see LICENSE.txt).
# The problems and expected plans are read from recorded/<case>.json, which record.py wrote by running
# the upstream example with find_plan wrapped, so no plan here is copied by hand.
# Run from the repository root: python3 -I tests/gtpyhop/generate_unigoal.py blocks_hgn   (or blocks_goal_splitting)
# GTPyhop's unigoal methods are tasks here: pos(x,y) and clear(x), each with an "already true" alternative first.
import json,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blocks_lib import *
CASE=sys.argv[1]; D="tests/gtpyhop/"+CASE+"/"
REC=json.load(open("tests/gtpyhop/recorded/"+CASE+".json"))
b2i=lambda g,c: g.r(g.n("type/boolToInt",{"a":c}))
def graphPos():
    g=GB(); x=g.var("x"); y=g.var("y"); yh=g.var("yh"); yt=g.var("yt"); yb=g.var("yb"); cur=g.var("cur"); pb=g.var("pb")
    root(g,g.seq([g.setv(yh,b2i(g,g.eq(g.get(y),g.I(HAND)))),g.setv(yt,b2i(g,g.eq(g.get(y),g.I(TABLE)))),
                  g.setv(yb,b2i(g,g.ge(g.get(y),g.I(0)))),g.setv(cur,g.ptr("/pos/[b]",b=g.get(x))),
                  g.setv(pb,b2i(g,g.ge(g.get(cur),g.I(0))))])); return g.out("pos")
def graphClearOf():
    g=GB(); x=g.var("x"); xt=g.var("xt"); found=g.var("found"); a=g.var("a")
    n=g.ptr("/count/blocks")
    def body(i):
        return g.branch(g.and_(g.eq(g.get(found),g.I(0)),g.eq(g.ptr("/pos/[b]",b=i),g.get(x))),g.seq([g.setv(found,g.I(1)),g.setv(a,i)]))
    root(g,g.seq([g.setv(xt,b2i(g,g.eq(g.get(x),g.I(TABLE)))),g.loop_for(g.I(0),n,body)])); return g.out("clear")
def graphSlot():
    g=GB(); x=g.var("x"); d=g.var("d"); u=g.var("u"); go=g.var("go")
    root(g,g.setv(go,g.get(u))); return g.out("slot")
SLOTS=4
def graphSplit():
    g=GB(); b=[g.var("b%d"%i) for i in range(SLOTS)]; d=[g.var("d%d"%i) for i in range(SLOTS)]
    u=[g.var("u%d"%i) for i in range(SLOTS)]; anyv=g.var("any"); parts=[]
    for i in range(SLOTS):
        parts.append(g.setv(b[i],g.I(i)))
        unmet=g.and_(g.not_(g.eq(g.get(d[i]),g.I(FREE))),g.not_(g.eq(g.get(d[i]),g.ptr("/pos/[b]",b=g.I(i)))))
        inner=g.seq([g.setv(d[i],g.ptr("/goal/[b]",b=g.I(i))),g.setv(u[i],b2i(g,unmet))])
        parts.append(g.branch(g.ge(g.ptr("/count/blocks"),g.I(i+1)),inner))
    tot=g.get(u[0])
    for i in range(1,SLOTS): tot=g.op("math/add",tot,g.get(u[i]))
    parts.append(g.setv(anyv,tot)); root(g,g.seq(parts)); return g.out("split")
gp=graphPos()
NOTHING_H=eqc("/holding/hand","nothing")
A_done={"name":"done","check":[eqc("/pos/[x]",P("y"))],"subtasks":[]}
A_pickup={"name":"pickup","graph":gp,"check":[eqc("/graph/yh",1),ge("/clear/[x]",1),NOTHING_H,eqc("/pos/[x]","table")],"subtasks":[["pickup",P("x")]]}
A_unstack={"name":"unstack","graph":gp,"check":[eqc("/graph/yh",1),ge("/clear/[x]",1),NOTHING_H,eqc("/graph/pb",1)],"subtasks":[["unstack",P("x"),P("cur")]]}
A_putdown={"name":"putdown","graph":gp,"check":[eqc("/graph/yt",1),eqc("/pos/[x]","hand")],"subtasks":[["putdown",P("x")]]}
A_stack={"name":"stack","graph":gp,"check":[eqc("/graph/yb",1),eqc("/pos/[x]","hand"),ge("/clear/[y]",1)],"subtasks":[["stack",P("x"),P("y")]]}
A_move_t={"name":"move1-to-table","graph":gp,"check":[eqc("/graph/yt",1),NOTHING_H],"subtasks":[["clear",P("x")],["pos",P("x"),"hand"],["pos",P("x"),"table"]]}
A_move_b={"name":"move1-to-block","graph":gp,"check":[eqc("/graph/yb",1),NOTHING_H],"subtasks":[["clear",P("y")],["clear",P("x")],["pos",P("x"),"hand"],["pos",P("x"),P("y")]]}
methods={}
if CASE=="blocks_hgn":
    TOP="moveblocks"
    methods["pos"]={"params":["x","y"],"alternatives":[A_done,A_pickup,A_unstack,A_putdown,A_stack]}
    methods[TOP]={"params":[],"alternatives":[
      {"name":"to-final-place","graph":graphA(),"check":[ge("/graph/found",1)],"subtasks":[["pos",P("x"),"hand"],["pos",P("x"),P("dest")],[TOP]]},
      {"name":"out-of-the-way","graph":graphB(),"check":[ge("/graph/found",1)],"subtasks":[["pos",P("x"),"hand"],["pos",P("x"),"table"],[TOP]]},
      {"name":"done","graph":graphC(),"check":[eqc("/graph/found",0)],"subtasks":[]}]}
else:
    TOP="split"
    methods["pos"]={"params":["x","y"],"alternatives":[A_done,A_move_t,A_move_b,A_pickup,A_unstack,A_putdown,A_stack]}
    gc=graphClearOf()
    methods["clear"]={"params":["x"],"alternatives":[
      {"name":"table","graph":gc,"check":[eqc("/graph/xt",1)],"subtasks":[]},
      {"name":"already-clear","check":[ge("/clear/[x]",1)],"subtasks":[]},
      {"name":"clear-what-is-above","graph":gc,"check":[ge("/graph/found",1)],"subtasks":[["clear",P("a")],["pos",P("a"),"table"]]}]}
    gs=graphSplit(); sl=graphSlot()
    methods["slot"]={"params":["x","d","u"],"alternatives":[
      {"name":"unmet","graph":sl,"check":[ge("/graph/go",1)],"subtasks":[["pos",P("x"),P("d")]]},
      {"name":"met-at-split-time","graph":sl,"check":[eqc("/graph/go",0)],"subtasks":[]}]}
    methods[TOP]={"params":[],"alternatives":[
      {"name":"achieve-each-then-recheck","graph":gs,"check":[ge("/graph/any",1)],
       "subtasks":[["slot",P("b%d"%i),P("d%d"%i),P("u%d"%i)] for i in range(SLOTS)]+[[TOP]]},
      {"name":"done","graph":gs,"check":[eqc("/graph/any",0)],"subtasks":[]}]}
desc={"blocks_hgn":"GTPyhop's blocks_hgn. Its unigoal methods on pos are the task pos(x,y); the multigoal method moveblocks asks for pos(x,hand) and then pos(x,destination). ",
      "blocks_goal_splitting":"GTPyhop's blocks_goal_splitting. Its unigoal methods m_move1, m_get, m_put on pos and m_make_clear on clear are the tasks pos(x,y) and clear(x); GTPyhop's built-in m_split_multigoal is the task split, which fixes at split time which goals are unmet and achieves them in the multigoal's order, then asks again. The codebook lists the multigoal's blocks first, in its order. At most four blocks are split. Only the pos part of a multigoal is encoded. "}[CASE]
dom={"@context":CTX,"@type":"domain:Definition","name":CASE,"source":"GTPyhop examples/"+CASE,"version":"0.1.0",
 "description":desc+"A block is its index in the problem's codebook. pos is a block, table (-1) or hand (-2); clear is 0 or 1; holding is a block, or nothing (-4); the goal is goal/<block>, a block, table, or free (-3).",
 "enums":ENUMS,"variables":[{"name":n,"type":"int","init":{}} for n in ["pos","clear","holding","goal","count"]],
 "actions":ACTIONS,"methods":methods}
os.makedirs(D,exist_ok=True)
json.dump(dom,open(D+"domain.jsonld","w"),indent=1); open(D+"domain.jsonld","a").write("\n")
NAMES={"blocks_hgn":{0:"pickup-a",1:"pickup-b",2:"pos-b-hand",3:"pickup-c",4:"unstack-a-b",5:"pos-a-b",6:"pos-a-hand",7:"pos-c-hand",
                     8:"goal1a",9:"goal1b",10:"sussman",11:"goal2b-done",15:"goal2a",16:"goal2b",17:"goal3",18:"rand50"},
       "blocks_goal_splitting":{0:"goal1a",1:"goal1b",2:"goal2a",3:"goal2b"}}[CASE]
S=lambda v: v if v=="table" else str(v)
def step(a): return a[0]+"("+",".join(str(i) for i in a[1:])+")"
written=[]
for idx,name in NAMES.items():
    r=REC[idx]; st=r["state"]; order=[str(k) for k in r["order"]["clear"]]
    pos={str(k):S(v) for k,v in st["pos"].items()}; clear={str(k):bool(v) for k,v in st["clear"].items()}
    # a block upstream leaves out of state.clear (rand50 builds it with range(1,50)) gets its entry when first
    # unstacked, so it comes last in GTPyhop's dict order and starts not clear
    for k in pos:
        if k not in clear: clear[k]=False; order.append(k)
    t=r["todo"][0]
    if isinstance(t,dict): goal={str(k):S(v) for k,v in t["multigoal"]["pos"].items()}; todo=[[TOP]]
    else: goal={}; todo=[[str(i) for i in t]]
    if CASE=="blocks_goal_splitting":
        order=[b for b in goal]+[b for b in order if b not in goal]
    res=r["result"]; expect=["REFUSED:unreachable"] if res is False else [step(a) for a in res]
    write_problem(D,CASE,name,order,pos,clear,goal,todo,expect); written.append(name)
open(D+"cases","w").write("\n".join(written)+"\n")
